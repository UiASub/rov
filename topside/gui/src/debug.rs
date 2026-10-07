use crate::{App, Message, meter::Meter, panel, style};
use iced::widget::{button, column, row, scrollable, space, text};
use iced::{Element, Fill, Font};

pub fn view(app: &App) -> Element<'_, Message> {
    let sample = &app.sample;
    let toolbar = row![
        column![
            text("Sensor debug").size(22),
            text("Simulated samples · 10 Hz")
                .size(12)
                .color(style::MUTED)
        ]
        .spacing(5),
        space::horizontal(),
        text(format!("#{:06}   {:.1} s", sample.sequence, sample.time))
            .size(13)
            .font(Font::MONOSPACE)
            .color(style::MUTED),
        button(if app.frozen { "Resume" } else { "Freeze" })
            .on_press(Message::Freeze)
            .style(style::secondary)
            .padding([8, 16]),
    ]
    .spacing(16)
    .align_y(iced::Center);

    let pressure = panel(
        column![
            heading("Bar30 / Bar100", "Pressure / depth"),
            value("Pressure", format!("{:.3} kPa", sample.pressure)),
            value("Temperature", format!("{:.2} °C", sample.temperature)),
            value("Depth", format!("{:.3} m", sample.depth)),
            bar(sample.depth, 0.0, 30.0, style::ACCENT),
            scale("0", "Depth display scale · m", "30"),
        ]
        .spacing(14),
    );

    let dvl = panel(
        column![
            heading("DVL A50", "Body-frame velocity"),
            vector("Velocity", sample.velocity, "m/s", -0.5, 0.5, style::ACCENT),
            value("Altitude", format!("{:.3} m", sample.altitude)),
            value("Velocity valid", "True".into()),
            text("Beam ranges").size(13).color(style::MUTED),
            beam(1, sample.beam_ranges[0]),
            beam(2, sample.beam_ranges[1]),
            beam(3, sample.beam_ranges[2]),
            beam(4, sample.beam_ranges[3]),
            scale("0", "Range display scale · m", "5"),
        ]
        .spacing(14),
    );

    let imu = panel(
        column![
            heading("VN-100", "IMU / AHRS"),
            vector(
                "Acceleration",
                sample.accel,
                "m/s²",
                -12.0,
                12.0,
                style::ACCENT
            ),
            vector(
                "Angular velocity",
                sample.gyro,
                "rad/s",
                -0.02,
                0.02,
                style::GREEN
            ),
            vector(
                "Magnetic field",
                sample.mag,
                "µT",
                -60.0,
                60.0,
                style::AMBER
            ),
            text("Quaternion · w, x, y, z").size(13).color(style::MUTED),
            row![
                component("w", sample.quaternion[0]),
                component("x", sample.quaternion[1]),
                component("y", sample.quaternion[2]),
                component("z", sample.quaternion[3])
            ]
            .spacing(16),
            value("Heading", format!("{:.3}°", sample.heading)),
        ]
        .spacing(16),
    );

    let imaging = panel(
        column![
            heading("Imaging", "Cameras / sonar"),
            value("exploreHD", "Test pattern".into()),
            value("IMX307", "Test pattern".into()),
            value("ECHO", "Test pattern".into()),
            value("Sample sequence", sample.sequence.to_string()),
            value("Packet age", "—".into()),
            value("Packet loss", "—".into()),
        ]
        .spacing(14),
    );

    let command = panel(
        column![
            heading("Motion request", "surge / sway / heave / yaw"),
            command_axis("Surge", app.command[0]),
            command_axis("Sway", app.command[1]),
            command_axis("Heave", app.command[2]),
            command_axis("Yaw", app.command[3]),
            scale("−1", "Normalized input", "+1"),
        ]
        .spacing(12),
    );

    let left = column![pressure, dvl, command].spacing(16).width(Fill);
    let right = column![imu, imaging].spacing(16).width(Fill);
    let cards: Element<'_, Message> = if app.width < 1000.0 {
        column![left, right].spacing(16).into()
    } else {
        row![left, right].spacing(16).into()
    };
    column![toolbar, scrollable(cards).height(Fill)]
        .spacing(20)
        .height(Fill)
        .into()
}
fn heading<'a>(name: &'a str, description: &'a str) -> Element<'a, Message> {
    column![
        text(name).size(17),
        text(description).size(12).color(style::MUTED)
    ]
    .spacing(4)
    .into()
}
fn value<'a>(label: &'a str, value: String) -> Element<'a, Message> {
    row![
        text(label).size(13).color(style::MUTED),
        space::horizontal(),
        text(value).size(13).font(Font::MONOSPACE)
    ]
    .spacing(12)
    .into()
}
fn component(label: &'static str, value: f32) -> Element<'static, Message> {
    column![
        text(label).size(12).color(style::MUTED),
        text(format!("{value:+.4}")).size(13).font(Font::MONOSPACE)
    ]
    .spacing(5)
    .width(Fill)
    .into()
}
fn bar(value: f32, min: f32, max: f32, color: iced::Color) -> Element<'static, Message> {
    iced::widget::canvas(Meter {
        value,
        min,
        max,
        color,
    })
    .width(Fill)
    .height(12)
    .into()
}
fn scale<'a>(min: &'a str, label: &'a str, max: &'a str) -> Element<'a, Message> {
    row![
        text(min).size(11).color(style::MUTED),
        space::horizontal(),
        text(label).size(11).color(style::MUTED),
        space::horizontal(),
        text(max).size(11).color(style::MUTED)
    ]
    .into()
}
fn vector(
    name: &'static str,
    values: [f32; 3],
    units: &'static str,
    min: f32,
    max: f32,
    color: iced::Color,
) -> Element<'static, Message> {
    let mut content = column![row![
        text(name).size(13).color(style::MUTED),
        space::horizontal(),
        text(units).size(11).color(style::MUTED)
    ]]
    .spacing(10);
    for (axis, value) in ["X", "Y", "Z"].into_iter().zip(values) {
        content = content.push(
            row![
                text(axis).size(12).color(style::MUTED).width(14),
                bar(value, min, max, color),
                text(format!("{value:+.4}"))
                    .size(13)
                    .font(Font::MONOSPACE)
                    .width(82)
            ]
            .spacing(12)
            .align_y(iced::Center),
        );
    }
    content
        .push(scale_box(
            format!("{min:+}"),
            "Display scale",
            format!("{max:+}"),
        ))
        .into()
}
fn scale_box(min: String, label: &'static str, max: String) -> Element<'static, Message> {
    row![
        text(min).size(11).color(style::MUTED),
        space::horizontal(),
        text(label).size(11).color(style::MUTED),
        space::horizontal(),
        text(max).size(11).color(style::MUTED)
    ]
    .into()
}
fn beam(index: u8, range: f32) -> Element<'static, Message> {
    row![
        text(format!("{index:02}"))
            .size(12)
            .color(style::MUTED)
            .width(22),
        bar(range, 0.0, 5.0, style::ACCENT),
        text(format!("{range:.3} m"))
            .size(13)
            .font(Font::MONOSPACE)
            .width(84)
    ]
    .spacing(12)
    .align_y(iced::Center)
    .into()
}
fn command_axis(label: &'static str, value: f32) -> Element<'static, Message> {
    row![
        text(label).size(13).color(style::MUTED).width(58),
        bar(value, -1.0, 1.0, style::ACCENT),
        text(format!("{value:+.3}"))
            .size(13)
            .font(Font::MONOSPACE)
            .width(66)
    ]
    .spacing(12)
    .align_y(iced::Center)
    .into()
}
