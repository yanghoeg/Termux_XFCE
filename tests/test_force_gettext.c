#include "../assets/force_gettext.c"
#include <assert.h>

static void check(const char *input, const char *expected) {
    /* Exact allocation makes reading past the terminating NUL visible to ASan. */
    char *owned = strdup(input);
    char actual[128];
    assert(owned);
    normalize_key(owned, actual, sizeof(actual));
    if (strcmp(actual, expected)) {
        fprintf(stderr, "normalize: expected [%s], got [%s]\n", expected, actual);
        abort();
    }
    free(owned);
}

static void check_normalization(void) {
    check("a‘", "a'");
    check("a’", "a'");
    check("a“", "a\"");
    check("a”", "a\"");
    check("a–", "a-");
    check("a—", "a-");
    check("‘a’", "'a'");
    check("“a”", "\"a\"");
    check("a–b—c", "a-b-c");
    check("“”", "\"\"");
    check("_Save Changes", "save changes");
    check("\xe2", "\xe2");
    check("\xe2\x80", "\xe2\x80");
}


static const char *expected_context, *expected_message;
static const char *mock_dpgettext2(const char *domain, const char *context,
                                   const char *message) {
    assert(domain && !strcmp(domain, "thunar"));
    assert(context == expected_context && message == expected_message);
    return message;
}

static void check_overrides(const char *catalog_root) {
    static const struct { const char *message, *translation; } labels[] = {
        {"File", "파일"}, {"_File", "파일(_F)"},
        {"Edit", "편집"}, {"_Edit", "편집(_E)"},
        {"View", "보기"}, {"_View", "보기(_V)"},
        {"Go", "이동"}, {"_Go", "이동(_G)"},
        {"Bookmarks", "북마크"}, {"_Bookmarks", "북마크(_B)"},
        {"Help", "도움말"}, {"_Help", "도움말(_H)"},
        {"Save", "저장"}, {"_Save", "저장(_S)"}
    };
    assert(!setenv("FORCE_OVR_ALLOW", "thunar mousepad", 1));
    assert(!setenv("FORCE_TEXTDOMAINDIR", catalog_root, 1));
    unsetenv("FALLBACK_DOMAINS");
    for (size_t i = 0; i < sizeof(labels)/sizeof(labels[0]); ++i) {
        assert(!strcmp(dgettext("thunar", labels[i].message), labels[i].translation));
        assert(!strcmp(g_dpgettext2("thunar", "Menu", labels[i].message),
                       labels[i].translation));
    }

    /* Exercise both sides of the former 1200-byte buffer boundary. */
    static const size_t context_lengths[] = {1193, 1194, 1195, 1299};
    char context[1300];
    for (size_t i = 0; i < sizeof(context_lengths)/sizeof(context_lengths[0]); ++i) {
        memset(context, 'c', context_lengths[i]);
        context[context_lengths[i]] = '\0';
        assert(!strcmp(g_dpgettext2("thunar", context, "File"), "파일"));
    }
    /* Untranslated long inputs still reach the original hook without truncation. */
    char message[1300];
    memset(message, 'm', sizeof(message)-1);
    message[sizeof(message)-1] = '\0';
    rgdp2 = mock_dpgettext2;
    expected_context = context;
    expected_message = "review untranslated message";
    assert(g_dpgettext2("thunar", expected_context, expected_message) == expected_message);
    expected_context = "Menu";
    expected_message = message;
    assert(g_dpgettext2("thunar", expected_context, expected_message) == message);

    /* Only Thunar's untrusted-launcher warning becomes the launcher text. */
    static const char checkbox[] = "Allow this file to _run as a .desktop file";
    assert(!strcmp(dgettext("thunar", checkbox), checkbox));
    assert(!strcmp(dgettext("thunar", "Invalid desktop file"), "Invalid desktop file"));
    assert(TLS_IS_LAUNCHER == 0);
    const char *warning = dgettext("thunar", "The desktop file %s is in an insecure location "
        "and not marked as secure%s. If you do not trust this program, click Cancel.");
    assert(!strncmp(warning, "이 실행 아이콘은", strlen("이 실행 아이콘은")));
    assert(TLS_IS_LAUNCHER == 1);
    TLS_IS_LAUNCHER = 0;
}

enum { MO_SIZE = 160, ORIGINAL_TABLE = 29, TRANSLATION_TABLE = 37,
       ORIGINAL_STRING = 64, TRANSLATION_STRING = 100 };

static void put32(unsigned char *p, uint32_t value, int big_endian) {
    for (unsigned i = 0; i < 4; ++i)
        p[i] = (unsigned char)(value >> (big_endian ? 24 - i * 8 : i * 8));
}

static void mo_fixture(unsigned char *blob, int big_endian,
                       const char *original, size_t original_size,
                       const char *translation, size_t translation_size) {
    assert(original_size <= TRANSLATION_STRING - ORIGINAL_STRING);
    assert(translation_size <= MO_SIZE - TRANSLATION_STRING);
    memset(blob, 0, MO_SIZE);
    put32(blob, 0x950412de, big_endian);
    put32(blob + 8, 1, big_endian);
    /* Deliberately unaligned descriptor tables exercise portable word reads. */
    put32(blob + 12, ORIGINAL_TABLE, big_endian);
    put32(blob + 16, TRANSLATION_TABLE, big_endian);
    put32(blob + ORIGINAL_TABLE, original_size - 1, big_endian);
    put32(blob + ORIGINAL_TABLE + 4, ORIGINAL_STRING, big_endian);
    put32(blob + TRANSLATION_TABLE, translation_size - 1, big_endian);
    put32(blob + TRANSLATION_TABLE + 4, TRANSLATION_STRING, big_endian);
    memcpy(blob + ORIGINAL_STRING, original, original_size);
    memcpy(blob + TRANSLATION_STRING, translation, translation_size);
}

static Cat *read_fixture(const char *path, const unsigned char *blob, size_t size) {
    FILE *file = fopen(path, "wb");
    assert(file);
    assert(fwrite(blob, 1, size, file) == size);
    assert(fclose(file) == 0);
    return loadmo(path);
}

static void free_catalog(Cat *catalog) {
    if (!catalog) return;
    for (size_t i = 0; i < catalog->d->n; ++i) {
        Entry *entry = catalog->d->b[i];
        while (entry) {
            Entry *next = entry->next;
            free(entry->key);
            free(entry->val);
            free(entry);
            entry = next;
        }
    }
    free(catalog->d->b);
    free(catalog->d);
    free(catalog->blob);
    free(catalog);
}

static void assert_empty_catalog(Cat *catalog) {
    /* Invalid strings are skipped, retaining the loader's existing behavior. */
    assert(catalog);
    for (size_t i = 0; i < catalog->d->n; ++i) assert(!catalog->d->b[i]);
    free_catalog(catalog);
}

static void check_catalogs(const char *path) {
    static const char original[] = "catalog phrase";
    static const char translation[] = "번역값";
    static const char plural_original[] = "apple\0apples";
    static const char plural_translation[] = "사과\0사과들";
    unsigned char blob[MO_SIZE];
    Cat *catalog;

    for (int big_endian = 0; big_endian <= 1; ++big_endian) {
        mo_fixture(blob, big_endian, original, sizeof(original),
                   translation, sizeof(translation));
        catalog = read_fixture(path, blob, sizeof(blob));
        assert(catalog);
        assert(!strcmp(dict_get(catalog->d, original), translation));
        free_catalog(catalog);

        /* A terminating NUL in the last file byte is still in bounds. */
        put32(blob + TRANSLATION_TABLE + 4, sizeof(blob) - sizeof(translation), big_endian);
        memcpy(blob + sizeof(blob) - sizeof(translation), translation, sizeof(translation));
        catalog = read_fixture(path, blob, sizeof(blob));
        assert(catalog);
        assert(!strcmp(dict_get(catalog->d, original), translation));
        free_catalog(catalog);

        mo_fixture(blob, big_endian, "", 1, "", 1);
        catalog = read_fixture(path, blob, sizeof(blob));
        assert(catalog);
        assert(!strcmp(dict_get(catalog->d, ""), ""));
        free_catalog(catalog);

        mo_fixture(blob, big_endian, plural_original, sizeof(plural_original),
                   plural_translation, sizeof(plural_translation));
        catalog = read_fixture(path, blob, sizeof(blob));
        assert(catalog);
        assert(!strcmp(dict_get(catalog->d, "apple"), "사과"));
        free_catalog(catalog);

        /* Test both string descriptors: overflowing lengths, offsets outside
           the file, and missing NULs at their declared end. */
        for (int translated = 0; translated <= 1; ++translated) {
            size_t table = translated ? TRANSLATION_TABLE : ORIGINAL_TABLE;
            size_t offset = translated ? TRANSLATION_STRING : ORIGINAL_STRING;
            size_t length = translated ? sizeof(translation) - 1 : sizeof(original) - 1;

            mo_fixture(blob, big_endian, original, sizeof(original),
                       translation, sizeof(translation));
            put32(blob + table, UINT32_MAX, big_endian);
            memset(blob + offset, 'x', sizeof(blob) - offset);
            assert_empty_catalog(read_fixture(path, blob, sizeof(blob)));

            mo_fixture(blob, big_endian, original, sizeof(original),
                       translation, sizeof(translation));
            put32(blob + table + 4, UINT32_MAX, big_endian);
            assert_empty_catalog(read_fixture(path, blob, sizeof(blob)));

            mo_fixture(blob, big_endian, original, sizeof(original),
                       translation, sizeof(translation));
            put32(blob + table, 0, big_endian);
            put32(blob + table + 4, sizeof(blob), big_endian);
            assert_empty_catalog(read_fixture(path, blob, sizeof(blob)));

            mo_fixture(blob, big_endian, original, sizeof(original),
                       translation, sizeof(translation));
            put32(blob + table, sizeof(blob) - offset, big_endian);
            assert_empty_catalog(read_fixture(path, blob, sizeof(blob)));

            mo_fixture(blob, big_endian, original, sizeof(original),
                       translation, sizeof(translation));
            blob[offset + length] = 'x';
            assert_empty_catalog(read_fixture(path, blob, sizeof(blob)));

            mo_fixture(blob, big_endian, original, sizeof(original),
                       translation, sizeof(translation));
            put32(blob + table + 4, sizeof(blob) - 10, big_endian);
            put32(blob + table, 9, big_endian);
            memset(blob + sizeof(blob) - 10, 'x', 10);
            assert_empty_catalog(read_fixture(path, blob, sizeof(blob)));

            /* An interior plural separator cannot replace the final NUL. */
            mo_fixture(blob, big_endian, plural_original, sizeof(plural_original),
                       plural_translation, sizeof(plural_translation));
            length = translated ? sizeof(plural_translation) - 1 : sizeof(plural_original) - 1;
            blob[offset + length] = 'x';
            assert_empty_catalog(read_fixture(path, blob, sizeof(blob)));
        }

        for (int translated = 0; translated <= 1; ++translated) {
            mo_fixture(blob, big_endian, original, sizeof(original),
                       translation, sizeof(translation));
            put32(blob + (translated ? 16 : 12), UINT32_MAX, big_endian);
            assert(!read_fixture(path, blob, sizeof(blob)));

            mo_fixture(blob, big_endian, original, sizeof(original),
                       translation, sizeof(translation));
            put32(blob + (translated ? 16 : 12), sizeof(blob) - 7, big_endian);
            assert(!read_fixture(path, blob, sizeof(blob)));
        }

        mo_fixture(blob, big_endian, original, sizeof(original),
                   translation, sizeof(translation));
        put32(blob + 8, UINT32_MAX, big_endian);
        assert(!read_fixture(path, blob, sizeof(blob)));
        assert(!read_fixture(path, blob, 27));
    }
}

typedef struct {
    unsigned calls;
    int null_format;
    char format[16];
    char text[8192];
} DialogCall;

static DialogCall new_call, markup_new_call, secondary_text_call, secondary_markup_call;
static unsigned set_markup_calls;
static char primary_markup[8192];
static int dialog_object, parent_object;

static void record_dialog_call(DialogCall *call, const char *format, va_list args) {
    ++call->calls;
    call->null_format = format == NULL;
    call->format[0] = call->text[0] = '\0';
    if (format) {
        snprintf(call->format, sizeof(call->format), "%s", format);
        assert(vsnprintf(call->text, sizeof(call->text), format, args) >= 0);
    }
}

static void *mock_dialog_new(void *parent, int flags, int type, int buttons,
                             const char *format, ...) {
    assert(parent == &parent_object && flags == 1 && type == 2 && buttons == 3);
    va_list args;
    va_start(args, format);
    record_dialog_call(&new_call, format, args);
    va_end(args);
    return &dialog_object;
}

static void *mock_dialog_new_with_markup(void *parent, int flags, int type, int buttons,
                                         const char *format, ...) {
    assert(parent == &parent_object && flags == 1 && type == 2 && buttons == 3);
    va_list args;
    va_start(args, format);
    record_dialog_call(&markup_new_call, format, args);
    va_end(args);
    return &dialog_object;
}

static void mock_set_markup(void *dialog, const char *text) {
    assert(dialog == &dialog_object && text);
    ++set_markup_calls;
    snprintf(primary_markup, sizeof(primary_markup), "%s", text);
}

static void mock_secondary_text(void *dialog, const char *format, ...) {
    assert(dialog == &dialog_object);
    va_list args;
    va_start(args, format);
    record_dialog_call(&secondary_text_call, format, args);
    va_end(args);
}

static void mock_secondary_markup(void *dialog, const char *format, ...) {
    assert(dialog == &dialog_object);
    va_list args;
    va_start(args, format);
    record_dialog_call(&secondary_markup_call, format, args);
    va_end(args);
}

static char window_title[256];
static void mock_set_title(void *window, const char *title) {
    assert(window == &dialog_object && title);
    snprintf(window_title, sizeof(window_title), "%s", title);
}

/* Stand-in for g_markup_vprintf_escaped with one string argument. */
static unsigned markup_escape_calls;
static char *mock_markup_vprintf_escaped(const char *format, va_list args) {
    ++markup_escape_calls;
    assert(!strcmp(format, "<b>%s</b>"));
    const char *arg = va_arg(args, const char *);
    char *out = malloc(strlen(arg) * 5 + 8), *o = out;
    assert(out);
    o += sprintf(o, "<b>");
    for (; *arg; ++arg) {
        if (*arg == '<') o += sprintf(o, "&lt;");
        else if (*arg == '>') o += sprintf(o, "&gt;");
        else if (*arg == '&') o += sprintf(o, "&amp;");
        else *o++ = *arg;
    }
    sprintf(o, "</b>");
    return out;
}

static void check_whole_string_overrides(void) {
    real_gtk_window_set_title = mock_set_title;
    /* Titles and file names that merely contain a key keep their text. */
    static const char *const kept[] = {
        "user@phone: ~/scripts", "build_scripts.sh - Mousepad",
        "Request timed out - Mozilla Firefox", "Perl Scripts", "Python Scripts",
        "Open Terminal Here as Root",
    };
    for (size_t i = 0; i < sizeof(kept)/sizeof(kept[0]); ++i) {
        gtk_window_set_title(&dialog_object, kept[i]);
        assert(!strcmp(window_title, kept[i]));
    }
    gtk_window_set_title(&dialog_object, "Scripts");
    assert(!strcmp(window_title, "스크립트"));
    gtk_window_set_title(&dialog_object, "Timeout was reached");
    assert(!strcmp(window_title, "시간 제한에 도달했습니다"));
}

static void check_long_and_escaped_dialogs(void) {
    /* Longer than the former 2048-byte buffer, ending in multibyte text. */
    char long_text[3100];
    memset(long_text, 'a', 3000);
    strcpy(long_text + 3000, "끝까지 보존");
    gtk_message_dialog_new(&parent_object, 1, 2, 3, "%s", long_text);
    assert(!strcmp(new_call.text, long_text));
    gtk_message_dialog_format_secondary_text(&dialog_object, "%s", long_text);
    assert(!strcmp(secondary_text_call.text, long_text));
    gtk_message_dialog_format_secondary_markup(&dialog_object, "%s", long_text);
    assert(!strcmp(secondary_markup_call.text, long_text));

    /* The markup constructor escapes its arguments like GTK. */
    unsigned before = set_markup_calls;
    r_markup_vprintf_escaped = mock_markup_vprintf_escaped;
    gtk_message_dialog_new_with_markup(&parent_object, 1, 2, 3, "<b>%s</b>", "a<b>&c");
    r_markup_vprintf_escaped = NULL;
    assert(markup_escape_calls == 1);
    assert(!strcmp(new_call.text, "<b>a&lt;b&gt;&amp;c</b>"));
    assert(set_markup_calls == before + 1 && !strcmp(primary_markup, "<b>a&lt;b&gt;&amp;c</b>"));
}

static void check_dialogs(void) {
    real_gtk_message_dialog_new = mock_dialog_new;
    real_gtk_message_dialog_new_with_markup = mock_dialog_new_with_markup;
    real_gtk_message_dialog_set_markup = mock_set_markup;
    real_gtk_message_dialog_format_secondary_text = mock_secondary_text;
    real_gtk_message_dialog_format_secondary_markup = mock_secondary_markup;

    assert(gtk_message_dialog_new(&parent_object, 1, 2, 3, NULL) == &dialog_object);
    assert(new_call.calls == 1 && new_call.null_format);
    assert(gtk_message_dialog_new_with_markup(&parent_object, 1, 2, 3, NULL) == &dialog_object);
    assert(markup_new_call.calls == 1 && markup_new_call.null_format);
    assert(new_call.calls == 1 && set_markup_calls == 0);

    gtk_message_dialog_new(&parent_object, 1, 2, 3, "Item %s: %d%%", "value", 42);
    assert(!new_call.null_format && !strcmp(new_call.format, "%s"));
    assert(!strcmp(new_call.text, "Item value: 42%"));
    gtk_message_dialog_new(&parent_object, 1, 2, 3, "%s", "File");
    assert(!strcmp(new_call.text, "파일"));
    gtk_message_dialog_new_with_markup(&parent_object, 1, 2, 3, "<b>%s</b> %d%%", "value", 42);
    assert(!strcmp(new_call.text, "<b>value</b> 42%"));
    assert(set_markup_calls == 1 && !strcmp(primary_markup, "<b>value</b> 42%"));

    /* Ordinary constructors must not reinterpret file names or literal tags. */
    gtk_message_dialog_new(&parent_object, 1, 2, 3, "Could not read %s or %s",
                           "<missing>", "<other> & more");
    assert(!strcmp(new_call.text, "Could not read <missing> or <other> & more"));
    assert(set_markup_calls == 1);
    gtk_message_dialog_new(&parent_object, 1, 2, 3, "<b>%s</b>", "literal");
    assert(!strcmp(new_call.text, "<b>literal</b>"));
    assert(set_markup_calls == 1);

    /* Keep the intentional heading, including when gettext translated it first. */
    gtk_message_dialog_new(&parent_object, 1, 2, 3, "%s",
                           "Do you want to save the changes before closing?");
    assert(set_markup_calls == 2 && !strcmp(primary_markup, SAVE_CHANGES_MARKUP));
    gtk_message_dialog_new(&parent_object, 1, 2, 3, "%s", SAVE_CHANGES_MARKUP);
    assert(set_markup_calls == 3 && !strcmp(primary_markup, SAVE_CHANGES_MARKUP));

    gtk_message_dialog_format_secondary_text(&dialog_object, "Item %s: %d%%", "value", 42);
    assert(!secondary_text_call.null_format && !strcmp(secondary_text_call.format, "%s"));
    assert(!strcmp(secondary_text_call.text, "Item value: 42%"));
    gtk_message_dialog_format_secondary_text(&dialog_object, "%s", "File");
    assert(!strcmp(secondary_text_call.text, "파일"));
    gtk_message_dialog_format_secondary_text(&dialog_object, NULL);
    assert(secondary_text_call.null_format && !secondary_text_call.text[0]);
    gtk_message_dialog_format_secondary_text(&dialog_object, "");
    assert(!secondary_text_call.null_format && !secondary_text_call.text[0]);

    gtk_message_dialog_format_secondary_markup(&dialog_object, "<b>%s</b> %d%%", "value", 42);
    assert(!secondary_markup_call.null_format && !strcmp(secondary_markup_call.format, "%s"));
    assert(!strcmp(secondary_markup_call.text, "<b>value</b> 42%"));
    gtk_message_dialog_format_secondary_markup(&dialog_object, "%s", "File");
    assert(!strcmp(secondary_markup_call.text, "파일"));
    gtk_message_dialog_format_secondary_markup(&dialog_object, NULL);
    assert(secondary_markup_call.null_format && !secondary_markup_call.text[0]);
    gtk_message_dialog_format_secondary_markup(&dialog_object, "");
    assert(!secondary_markup_call.null_format && !secondary_markup_call.text[0]);

    check_long_and_escaped_dialogs();
    check_whole_string_overrides();
}

int main(int argc, char **argv) {
    const char *mode = argc > 1 ? argv[1] : "normalize";
    if (!strcmp(mode, "normalize")) check_normalization();
    else if (!strcmp(mode, "overrides")) {
        assert(argc == 3);
        check_overrides(argv[2]);
    } else if (!strcmp(mode, "mo")) {
        assert(argc == 3);
        check_catalogs(argv[2]);
    } else if (!strcmp(mode, "gtk")) check_dialogs();
    else return 2;
    return 0;
}
