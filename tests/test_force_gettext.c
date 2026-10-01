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
    char text[2048];
} DialogCall;

static DialogCall new_call, markup_new_call, secondary_text_call, secondary_markup_call;
static unsigned set_markup_calls;
static char primary_markup[2048];
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
}

int main(int argc, char **argv) {
    const char *mode = argc > 1 ? argv[1] : "normalize";
    if (!strcmp(mode, "normalize")) check_normalization();
    else if (!strcmp(mode, "mo")) {
        assert(argc == 3);
        check_catalogs(argv[2]);
    } else if (!strcmp(mode, "gtk")) check_dialogs();
    else return 2;
    return 0;
}
