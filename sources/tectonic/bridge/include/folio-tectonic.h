#include <stdint.h>

// 돌려주는 값의 뜻은 다음과 같다. 0은 빌드 성공, 1은 Tectonic이 보고한 오류(내용은 로그에 있다), 2는 Tectonic의 panic이다.
// `*out_log`는 항상 설정되며, 다 쓴 뒤 folio_tectonic_free_string에 넘겨 해제해야 한다.
int32_t folio_tectonic_compile(const char *input_path, const char *outdir, const char *cache_dir, int32_t only_cached,
                               int64_t source_date_epoch, char **out_log);
void folio_tectonic_free_string(char *s);
