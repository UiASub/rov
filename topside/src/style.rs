use iced::widget::{button, container};
use iced::{Border, Color, Theme};

// UiASub website sea palette, with separate interaction and status colors.
pub const BACKGROUND: Color = Color::from_rgb8(0x00, 0x10, 0x1a);
pub const SURFACE: Color = Color::from_rgb8(0x08, 0x20, 0x30);
pub const RAISED: Color = Color::from_rgb8(0x10, 0x30, 0x45);
pub const BORDER: Color = Color::from_rgb8(0x22, 0x43, 0x58);
pub const TEXT: Color = Color::from_rgb8(0xe6, 0xf7, 0xff);
pub const MUTED: Color = Color::from_rgb8(0x9a, 0xb3, 0xc3);
pub const ACCENT: Color = Color::from_rgb8(0x44, 0xb8, 0xff);
pub const GREEN: Color = Color::from_rgb8(0x61, 0xd6, 0xa4);
pub const RED: Color = Color::from_rgb8(0xff, 0x89, 0x89);
pub const AMBER: Color = Color::from_rgb8(0xee, 0xc0, 0x73);

pub fn theme() -> Theme {
    Theme::custom_with_fn(
        "UiASub",
        iced::theme::Palette {
            background: BACKGROUND,
            text: TEXT,
            primary: ACCENT,
            success: GREEN,
            danger: RED,
            warning: AMBER,
        },
        |palette| {
            let mut extended = iced::theme::palette::Extended::generate(palette);
            extended.background.weak = iced::theme::palette::Pair::new(SURFACE, TEXT);
            extended.background.strong = iced::theme::palette::Pair::new(RAISED, TEXT);
            extended
        },
    )
}

pub fn panel(_: &Theme) -> container::Style {
    container::Style {
        background: Some(SURFACE.into()),
        text_color: Some(TEXT),
        border: Border {
            color: BORDER,
            width: 1.0,
            radius: 8.0.into(),
        },
        ..Default::default()
    }
}
pub fn secondary(_: &Theme, status: button::Status) -> button::Style {
    button_style(status, SURFACE, RAISED, MUTED, BORDER)
}
pub fn primary(_: &Theme, status: button::Status) -> button::Style {
    button_style(
        status,
        RAISED,
        Color::from_rgb8(0x17, 0x43, 0x60),
        ACCENT,
        ACCENT.scale_alpha(0.55),
    )
}
pub fn danger(_: &Theme, status: button::Status) -> button::Style {
    button_style(
        status,
        Color::from_rgb8(0x32, 0x22, 0x30),
        Color::from_rgb8(0x49, 0x28, 0x36),
        RED,
        RED.scale_alpha(0.4),
    )
}
fn button_style(
    status: button::Status,
    base: Color,
    hover: Color,
    foreground: Color,
    border: Color,
) -> button::Style {
    button::Style {
        background: Some(
            if status == button::Status::Hovered {
                hover
            } else {
                base
            }
            .into(),
        ),
        text_color: foreground,
        border: Border {
            color: border,
            width: 1.0,
            radius: 5.0.into(),
        },
        ..Default::default()
    }
}
