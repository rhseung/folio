#include <stdint.h>

// 0: built, 1: Tectonic reported an error (in the log), 2: Tectonic panicked. `*out_log` is always set and must be
// handed back to folio_tectonic_free_string.
int32_t folio_tectonic_compile(const char *input_path, const char *outdir, const char *cache_dir, int32_t only_cached,
                               int64_t source_date_epoch, char **out_log);
void folio_tectonic_free_string(char *s);
