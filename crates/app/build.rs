use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};

fn main() {
    embed_windows_icon();
    let qml_files = qml_files();
    CxxQtBuilder::new_qml_module(QmlModule::new("StickyNotes").qml_files(qml_files))
        .qt_module("Quick")
        .files(["src/controller.rs"])
        .build();
}

/// Every `*.qml` file in `qml/`, sorted so the module is stable; `Theme.qml` is the
/// singleton. Adding a view means adding the file: no list to maintain. Test helpers
/// live under `tests/qml`, never here.
fn qml_files() -> Vec<QmlFile> {
    println!("cargo:rerun-if-changed=qml");
    let mut names: Vec<String> = std::fs::read_dir("qml")
        .expect("failed to read the qml directory")
        .map(|entry| entry.expect("failed to read a qml directory entry").path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "qml"))
        .map(|path| path.file_name().unwrap().to_string_lossy().into_owned())
        .collect();
    names.sort();
    names
        .into_iter()
        .map(|name| {
            let file = QmlFile::from(format!("qml/{name}"));
            if name == "Theme.qml" {
                file.singleton(true)
            } else {
                file
            }
        })
        .collect()
}

/// Embed the application icon into the Windows executable. The build script runs on
/// the host, so the target check uses the variable cargo sets, not `cfg!`.
#[cfg(windows)]
fn embed_windows_icon() {
    println!("cargo:rerun-if-changed=windows/stickynotes.rc");
    println!("cargo:rerun-if-changed=../../scripts/packaging/icon.ico");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        embed_resource::compile("windows/stickynotes.rc", embed_resource::NONE)
            .manifest_required()
            .expect("failed to embed the Windows icon resource");
    }
}

#[cfg(not(windows))]
fn embed_windows_icon() {}
