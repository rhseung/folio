// `tectonic -X compile -Z continue-on-errors --synctex [--only-cached] --outdir <dir> <file>`과 같은 일을 하고, 그 CLI가
// 출력하는 줄을 그대로 남긴다. `TexLog`가 이 출력을 CLI의 출력과 똑같이 읽기 때문이다.
use std::ffi::{c_char, CStr, CString};
use std::fmt::{Arguments, Write as _};
use std::path::PathBuf;
use std::sync::{Mutex, Once};

use tectonic::config::PersistentConfig;
use tectonic::driver::{OutputFormat, ProcessingSessionBuilder};
use tectonic::errors::Error;
use tectonic::status::{MessageKind, StatusBackend};
use tectonic::unstable_opts::UnstableOptions;

// xdvipdfmx는 PDF의 날짜를 환경 변수 SOURCE_DATE_EPOCH에서 읽으므로, 빌드는 이 값을 프로세스 전체에 설정한다. 두 빌드가
// 동시에 돌면 서로의 PDF에 상대의 날짜가 찍힌다.
static ONE_BUILD: Mutex<()> = Mutex::new(());

// 엔진의 `extern "C"` 콜백 안에서 난 panic은 C 쪽으로 unwind할 수 없어서, Rust가 `catch_unwind`보다 먼저 앱을 중단시키고
// 기본 hook이 stderr에 쓴 한 줄만 남는다. 메시지를 따로 저장해 두면, unwind되는 panic은 그 메시지가 빌드 로그에 남는다.
static LAST_PANIC: Mutex<Option<String>> = Mutex::new(None);
static HOOK: Once = Once::new();

fn record_panics() {
    HOOK.call_once(|| {
        let default = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            if let Ok(mut last) = LAST_PANIC.lock() {
                *last = Some(info.to_string());
            }
            default(info);
        }));
    });
}

#[derive(Default)]
struct Collect(String);

impl StatusBackend for Collect {
    fn report(&mut self, kind: MessageKind, args: Arguments, err: Option<&Error>) {
        let prefix = match kind {
            MessageKind::Note => "note:",
            MessageKind::Warning => "warning:",
            MessageKind::Error => "error:",
        };
        let _ = writeln!(self.0, "{prefix} {args}");
        if let Some(e) = err {
            for item in e.chain() {
                let _ = writeln!(self.0, "caused by: {item}");
            }
        }
    }

    fn note_highlighted(&mut self, before: &str, highlighted: &str, after: &str) {
        let _ = writeln!(self.0, "{before}{highlighted}{after}");
    }

    fn dump_error_logs(&mut self, output: &[u8]) {
        self.0.push_str("===============================================================================\n");
        self.0.push_str(&String::from_utf8_lossy(output));
        self.0.push_str("===============================================================================\n");
    }
}

fn compile(input: PathBuf, outdir: PathBuf, cache: PathBuf, only_cached: bool, epoch: i64, out: &mut Collect) -> Result<(), Error> {
    std::env::set_var("SOURCE_DATE_EPOCH", epoch.to_string());
    let config = PersistentConfig::default();
    let mut unstable = UnstableOptions::default();
    unstable.continue_on_errors = true;
    let name = input.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let root = input.parent().map(PathBuf::from).unwrap_or_default();

    let mut b = ProcessingSessionBuilder::default();
    b.unstables(unstable)
        .format_name("latex")
        .keep_logs(false)
        .keep_intermediates(false)
        // CLI가 캐시 루트 아래에 쓰는 폴더와 같아야 Mac에서 Homebrew Tectonic과 캐시 하나를 함께 쓴다.
        .format_cache_path(cache.join("formats"))
        .synctex(true)
        .output_format(OutputFormat::Pdf)
        .primary_input_path(&input)
        .tex_input_name(&name)
        .filesystem_root(root)
        .output_dir(&outdir)
        .print_stdout(false)
        .shell_escape_disabled();
    if only_cached {
        tectonic::tt_note!(out, "using only cached resource files");
    }
    let bundle = tectonic_bundles::detect_bundle(config.default_bundle_loc().to_owned(), only_cached, Some(cache.join("bundles")))?
        .ok_or_else(|| tectonic::errors::Error::msg("no bundle for the default bundle location"))?;
    b.bundle(bundle);
    b.build_date_from_env(false);

    let mut sess = b.create(out)?;
    let result = sess.run(out);
    if let Err(e) = &result {
        if let Some(err) = e.downcast_ref::<tectonic::errors::EngineError>() {
            let output = sess.get_stdout_content();
            if output.is_empty() {
                tectonic::tt_error!(out, "something bad happened inside {}, but no output was logged", err.engine());
            } else {
                tectonic::tt_error!(out, "something bad happened inside {}; its output follows:\n", err.engine());
                out.dump_error_logs(&output);
            }
        }
    }
    result.map(|_| ())
}

unsafe fn path(p: *const c_char) -> PathBuf {
    PathBuf::from(CStr::from_ptr(p).to_string_lossy().into_owned())
}

#[no_mangle]
pub unsafe extern "C" fn folio_tectonic_compile(input: *const c_char, outdir: *const c_char, cache: *const c_char, only_cached: i32, epoch: i64, out_log: *mut *mut c_char) -> i32 {
    let (input, outdir, cache) = (path(input), path(outdir), path(cache));
    let mut out = Collect::default();
    record_panics();
    let guard = ONE_BUILD.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    let code = match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| compile(input, outdir, cache, only_cached != 0, epoch, &mut out))) {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            out.report_error(&e);
            1
        }
        Err(_) => {
            let message = LAST_PANIC.lock().ok().and_then(|mut last| last.take()).unwrap_or_default();
            let _ = writeln!(out.0, "error: Tectonic panicked: {message}");
            2
        }
    };
    drop(guard);
    if !out_log.is_null() {
        *out_log = CString::new(out.0.replace('\0', " ")).unwrap_or_default().into_raw();
    }
    code
}

#[no_mangle]
pub unsafe extern "C" fn folio_tectonic_free_string(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}
