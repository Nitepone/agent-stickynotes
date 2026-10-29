use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};

fn main() {
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
        QmlFile::from("qml/SectionLabel.qml"),
        QmlFile::from("qml/FormTextArea.qml"),
    ];
    CxxQtBuilder::new_qml_module(QmlModule::new("StickyNotes").qml_files(qml_files))
        .qt_module("Quick")
        .files(["src/controller.rs"])
        .build();
}
