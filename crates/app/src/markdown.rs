//! Markdown to the HTML subset Qt's rich text shows, for the artifact viewer.
//!
//! Qt's own Markdown mode cannot set paragraph spacing or line height, but its
//! rich text can (a CSS subset), so the viewer styles this HTML itself.
//! Artifacts are written by agents, so nothing in them is trusted: raw HTML is
//! shown as text, and images (which Qt would try to load from disk or the
//! network) are replaced by their alt text.

use pulldown_cmark::{Event, Options, Parser, Tag, TagEnd, html};

pub fn to_html(markdown: &str) -> String {
    let options = Options::ENABLE_TABLES | Options::ENABLE_STRIKETHROUGH;
    let events = Parser::new_ext(markdown, options).filter_map(|event| match event {
        Event::Html(text) | Event::InlineHtml(text) => Some(Event::Text(text)),
        // The alt text arrives as ordinary text events between the two.
        Event::Start(Tag::Image { .. }) | Event::End(TagEnd::Image) => None,
        other => Some(other),
    });
    let mut out = String::new();
    html::push_html(&mut out, events);
    // Qt draws table borders only when asked to, and needs the spacing here.
    out.replace(
        "<table>",
        r#"<table border="1" cellspacing="0" cellpadding="6">"#,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renders_the_common_elements() {
        let html =
            to_html("# Title\n\nSome **bold** and `code`.\n\n- a\n- b\n\n```\nlet x = 1;\n```\n");
        assert!(html.contains("<h1>Title</h1>"));
        assert!(html.contains("<strong>bold</strong>"));
        assert!(html.contains("<code>code</code>"));
        assert!(html.contains("<li>a</li>"));
        assert!(html.contains("<pre><code>let x = 1;"));
    }

    #[test]
    fn tables_and_strikethrough_work() {
        let html = to_html("| a | b |\n|---|---|\n| 1 | 2 |\n\n~~gone~~");
        assert!(html.contains(r#"<table border="1""#));
        assert!(html.contains("<th>a</th>"));
        assert!(html.contains("<del>gone</del>"));
    }

    #[test]
    fn raw_html_is_shown_not_interpreted() {
        let html =
            to_html("<script>alert(1)</script>\n\nhi <b>there</b> <img src=\"/etc/passwd\">");
        assert!(!html.contains("<script"));
        assert!(!html.contains("<img"));
        assert!(html.contains("&lt;script&gt;"));
        assert!(html.contains("&lt;b&gt;"));
    }

    #[test]
    fn images_become_their_alt_text() {
        let html = to_html("![the diagram](file:///etc/passwd)");
        assert!(!html.contains("<img"));
        assert!(!html.contains("passwd"));
        assert!(html.contains("the diagram"));
    }

    #[test]
    fn links_keep_their_text() {
        let html = to_html("[docs](https://example.com)");
        assert!(html.contains(">docs</a>"));
    }
}
