use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};

fn main() {
    embed_windows_icon();
    let qml_files = [
        QmlFile::from("qml/Main.qml"),
        QmlFile::from("qml/Theme.qml").singleton(true),
        QmlFile::from("qml/BoardView.qml"),
        QmlFile::from("qml/ColumnView.qml"),
        QmlFile::from("qml/TaskCard.qml"),
        QmlFile::from("qml/TrashCan.qml"),
        QmlFile::from("qml/TaskDialog.qml"),
        QmlFile::from("qml/ColumnDialog.qml"),
        QmlFile::from("qml/ConfirmDialog.qml"),
        QmlFile::from("qml/ProjectDialog.qml"),
        QmlFile::from("qml/ProjectPicker.qml"),
        QmlFile::from("qml/ArtifactViewer.qml"),
        QmlFile::from("qml/ArtifactsPage.qml"),
        QmlFile::from("qml/PreferencesSection.qml"),
        QmlFile::from("qml/PreferencesPage.qml"),
        QmlFile::from("qml/ColorChoice.qml"),
        QmlFile::from("qml/GlowTracker.qml"),
        QmlFile::from("qml/GlowEdge.qml"),
        QmlFile::from("qml/PersonalizationSection.qml"),
        QmlFile::from("qml/SectionLabel.qml"),
        QmlFile::from("qml/FormTextArea.qml"),
        QmlFile::from("qml/WrappingField.qml"),
        QmlFile::from("qml/EditorSection.qml"),
        QmlFile::from("qml/ToolIcon.qml"),
        QmlFile::from("qml/IconButton.qml"),
        QmlFile::from("qml/SpellUnderline.qml"),
    ];
    CxxQtBuilder::new_qml_module(QmlModule::new("StickyNotes").qml_files(qml_files))
        .qt_module("Quick")
        .files(["src/controller.rs"])
        .build();
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
