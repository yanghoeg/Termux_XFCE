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

int main(void) {
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
    return 0;
}
