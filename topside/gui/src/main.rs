mod debug;
mod meter;
mod preview;
mod sensors;
mod style;

use iced::widget::{button, column, container, pick_list, row, slider, space, text};
use iced::{Element, Fill, Subscription};
use std::time::{Duration, Instant};
use style::{ACCENT, MUTED};

fn main() -> iced::Result {
    iced::application(App::default, App::update, App::view)
        .title("UiASub · Topside")
        .theme(|_: &App| style::theme())
        .subscription(App::subscription)
        .window_size((1360.0, 860.0))
        .run()
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Source {
    ExploreHd,
    Fisheye,
    Sonar,
    None,
}
impl Source {
    const ALL: [Self; 4] = [Self::ExploreHd, Self::Fisheye, Self::Sonar, Self::None];
}
impl std::fmt::Display for Source {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Self::ExploreHd => "exploreHD",
            Self::Fisheye => "IMX307 · Fisheye",
            Self::Sonar => "ECHO · Sonar",
            Self::None => "Unassigned",
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Page {
    Pilot,
    Debug,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Mode {
    Manual,
    Automation,
}
#[derive(Debug, Clone)]
enum Message {
    Page(Page),
    Freeze,
    Resize(iced::Size),
    Tick(Instant),
    Layout(usize),
    Source(usize, Source),
    Mode(Mode),
    Axis(usize, f32),
    Arm,
    Neutral,
}

struct App {
    started: Instant,
    page: Page,
    width: f32,
    frozen: bool,
    sample: sensors::Sample,
    sequence: u64,
    elapsed: f32,
    views: usize,
    sources: [Source; 4],
    mode: Mode,
    armed: bool,
    // Motion request, not quaternion components.
    command: [f32; 4],
}
impl Default for App {
    fn default() -> Self {
        Self {
            started: Instant::now(),
            page: Page::Pilot,
            width: 1360.0,
            frozen: false,
            sample: sensors::Sample::demo(0.0, 0),
            sequence: 0,
            elapsed: 0.0,
            views: 2,
            sources: [
                Source::ExploreHd,
                Source::Fisheye,
                Source::Sonar,
                Source::None,
            ],
            mode: Mode::Manual,
            armed: false,
            command: [0.0; 4],
        }
    }
}
impl App {
    fn subscription(&self) -> Subscription<Message> {
        Subscription::batch([
            iced::time::every(Duration::from_millis(100)).map(Message::Tick),
            iced::window::resize_events().map(|(_, size)| Message::Resize(size)),
        ])
    }
    fn update(&mut self, message: Message) {
        match message {
            Message::Page(page) => self.page = page,
            Message::Freeze => self.frozen = !self.frozen,
            Message::Resize(size) => self.width = size.width,
            Message::Tick(now) => {
                self.elapsed = now.duration_since(self.started).as_secs_f32();
                self.sequence += 1;
                if !self.frozen {
                    self.sample = sensors::Sample::demo(self.elapsed, self.sequence);
                }
                if self.armed && self.mode == Mode::Automation {
                    self.command = [
                        0.25,
                        0.10 * (self.elapsed * 0.4).sin(),
                        0.0,
                        0.15 * (self.elapsed * 0.2).cos(),
                    ];
                }
            }
            Message::Layout(views) => self.views = views,
            Message::Source(index, source) => self.sources[index] = source,
            Message::Mode(mode) => {
                self.mode = mode;
                self.armed = false;
                self.command = [0.0; 4];
            }
            Message::Axis(index, value) if self.armed && self.mode == Mode::Manual => {
                self.command[index] = value
            }
            Message::Axis(..) => {}
            Message::Arm => {
                self.armed = !self.armed;
                self.command = [0.0; 4];
            }
            Message::Neutral => {
                self.armed = false;
                self.command = [0.0; 4];
            }
        }
    }
    fn view(&self) -> Element<'_, Message> {
        let header = row![
            column![
                text("UiASub").size(24),
                text("TOPSIDE").size(11).color(MUTED)
            ]
            .spacing(3),
            row![
                button("Pilot")
                    .padding([8, 20])
                    .on_press(Message::Page(Page::Pilot))
                    .style(if self.page == Page::Pilot {
                        style::primary
                    } else {
                        style::secondary
                    }),
                button("Debug")
                    .padding([8, 20])
                    .on_press(Message::Page(Page::Debug))
                    .style(if self.page == Page::Debug {
                        style::primary
                    } else {
                        style::secondary
                    }),
            ]
            .spacing(8),
            space::horizontal(),
            text("SIMULATION").size(12).color(ACCENT),
            text(format!(
                "{:02}:{:02}",
                self.elapsed as u64 / 60,
                self.elapsed as u64 % 60
            ))
            .size(14),
        ]
        .spacing(24)
        .align_y(iced::Center);
        let mut layout = row![text("Views").size(13).color(MUTED)]
            .spacing(6)
            .align_y(iced::Center);
        for count in [1, 2, 4] {
            layout = layout.push(
                button(text(count.to_string()).size(13))
                    .padding([6, 14])
                    .style(if self.views == count {
                        style::primary
                    } else {
                        style::secondary
                    })
                    .on_press(Message::Layout(count)),
            );
        }
        let streams: Element<'_, Message> = match self.views {
            1 => self.stream(0),
            2 if self.width < 1100.0 => column![self.stream(0), self.stream(1)]
                .spacing(12)
                .height(Fill)
                .into(),
            2 => row![self.stream(0), self.stream(1)]
                .spacing(12)
                .height(Fill)
                .into(),
            _ => column![
                row![self.stream(0), self.stream(1)]
                    .spacing(12)
                    .height(Fill),
                row![self.stream(2), self.stream(3)]
                    .spacing(12)
                    .height(Fill),
            ]
            .spacing(12)
            .height(Fill)
            .into(),
        };
        let video = column![layout, streams]
            .spacing(12)
            .width(Fill)
            .height(Fill);
        let body: Element<'_, Message> = match self.page {
            Page::Pilot => row![video, self.sidebar()].spacing(20).height(Fill).into(),
            Page::Debug => debug::view(self),
        };
        let footer = row![
            text("JETSON  —").size(12).color(MUTED),
            text("MCU  —").size(12).color(MUTED),
            text("JOYSTICK  —").size(12).color(MUTED),
            button("Disarm")
                .on_press(Message::Neutral)
                .style(style::danger),
            space::horizontal(),
            text("SURGE / SWAY / HEAVE / YAW").size(11).color(MUTED)
        ]
        .spacing(24);
        container(column![header, body, footer].spacing(24))
            .padding(24)
            .height(Fill)
            .into()
    }
    fn stream(&self, index: usize) -> Element<'_, Message> {
        let source = self.sources[index];
        let header = row![
            text(format!("{:02}", index + 1)).size(12).color(MUTED),
            pick_list(Source::ALL, Some(source), move |source| Message::Source(
                index, source
            ))
            .text_size(13),
            space::horizontal(),
            text("DEMO").size(11).color(MUTED)
        ]
        .spacing(10)
        .align_y(iced::Center);
        let canvas = iced::widget::canvas(preview::Preview {
            source,
            elapsed: self.elapsed,
        })
        .width(Fill)
        .height(Fill);
        container(column![header, canvas].spacing(12))
            .padding(12)
            .width(Fill)
            .height(Fill)
            .style(style::panel)
            .into()
    }
    fn sidebar(&self) -> Element<'_, Message> {
        let modes = row![
            button("Manual")
                .on_press(Message::Mode(Mode::Manual))
                .style(if self.mode == Mode::Manual {
                    style::primary
                } else {
                    style::secondary
                }),
            button("Automation")
                .on_press(Message::Mode(Mode::Automation))
                .style(if self.mode == Mode::Automation {
                    style::primary
                } else {
                    style::secondary
                }),
        ]
        .spacing(8);
        let mut controls = column![
            text("Control").size(18),
            modes,
            row![
                text(if self.armed { "ARMED" } else { "DISARMED" })
                    .size(12)
                    .color(if self.armed { ACCENT } else { MUTED }),
                space::horizontal(),
                button(if self.armed { "Disarm" } else { "Arm" })
                    .on_press(Message::Arm)
                    .style(style::secondary)
            ]
            .align_y(iced::Center),
        ]
        .spacing(16);
        for (index, label) in ["Surge", "Sway", "Heave", "Yaw"].into_iter().enumerate() {
            let input: Element<'_, Message> = if self.armed && self.mode == Mode::Manual {
                slider(-1.0..=1.0, self.command[index], move |value| {
                    Message::Axis(index, value)
                })
                .step(0.01_f32)
                .into()
            } else {
                iced::widget::canvas(meter::Meter {
                    value: self.command[index],
                    min: -1.0,
                    max: 1.0,
                    color: ACCENT,
                })
                .width(Fill)
                .height(12)
                .into()
            };
            controls = controls.push(
                column![
                    row![
                        text(label).size(13),
                        space::horizontal(),
                        text(format!("{:+.2}", self.command[index]))
                            .size(13)
                            .color(ACCENT)
                    ],
                    input,
                ]
                .spacing(8),
            );
        }
        controls = controls.push(
            button("Neutral / disarm")
                .on_press(Message::Neutral)
                .style(style::danger)
                .width(Fill)
                .padding(10),
        );
        let telemetry = column![
            text("Telemetry").size(18),
            metric("Depth", &format!("{:.2} m", self.sample.depth)),
            metric("Heading", &format!("{:.1}°", self.sample.heading)),
            metric(
                "DVL velocity",
                &format!("{:.2} m/s", self.sample.velocity[0])
            ),
            metric(
                "Pressure",
                &format!("{:.2} bar", self.sample.pressure / 100.0)
            ),
            metric("Attitude", "Level"),
        ]
        .spacing(16);
        let sensors = column![
            text("Sensors").size(18),
            metric("DVL A50", "Demo"),
            metric("Bar30 / Bar100", "Demo"),
            metric("VN-100", "Demo"),
            metric("ECHO", "Demo"),
        ]
        .spacing(12);
        iced::widget::scrollable(
            column![panel(controls), panel(telemetry), panel(sensors)].spacing(12),
        )
        .width(280)
        .height(Fill)
        .into()
    }
}
fn metric<'a>(label: &'a str, value: &str) -> Element<'a, Message> {
    row![
        text(label).size(13).color(MUTED),
        space::horizontal(),
        text(value.to_owned()).size(13)
    ]
    .into()
}
fn panel<'a>(content: impl Into<Element<'a, Message>>) -> Element<'a, Message> {
    container(content)
        .padding(18)
        .width(Fill)
        .style(style::panel)
        .into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn freezing_sensor_display_keeps_control_timing_active() {
        let mut app = App::default();
        app.update(Message::Mode(Mode::Automation));
        app.update(Message::Arm);
        app.update(Message::Freeze);
        app.update(Message::Page(Page::Debug));
        app.update(Message::Tick(app.started + Duration::from_secs(1)));
        assert_eq!(app.sample.sequence, 0);
        assert_ne!(app.command, [0.0; 4]);
        assert!(app.armed);
        app.update(Message::Freeze);
        app.update(Message::Tick(app.started + Duration::from_secs(2)));
        assert_eq!(app.sample.sequence, 2);
        assert_eq!(app.sample.time, 2.0);
    }

    #[test]
    fn disarm_and_mode_changes_prevent_retaining_motion() {
        let mut app = App::default();
        app.update(Message::Arm);
        app.update(Message::Axis(0, 0.8));
        assert_eq!(app.command[0], 0.8);
        app.update(Message::Mode(Mode::Automation));
        assert!(!app.armed);
        assert_eq!(app.command, [0.0; 4]);
        app.update(Message::Arm);
        app.update(Message::Tick(app.started + Duration::from_secs(1)));
        assert_ne!(app.command, [0.0; 4]);
        app.update(Message::Neutral);
        app.update(Message::Tick(app.started + Duration::from_secs(2)));
        assert!(!app.armed);
        assert_eq!(app.command, [0.0; 4]);
    }

    #[test]
    fn manual_input_cannot_override_automation_or_disarmed_state() {
        let mut app = App::default();
        app.update(Message::Axis(0, 1.0));
        assert_eq!(app.command, [0.0; 4]);
        app.update(Message::Mode(Mode::Automation));
        app.update(Message::Arm);
        app.update(Message::Tick(app.started + Duration::from_secs(1)));
        let automation = app.command;
        app.update(Message::Axis(0, 1.0));
        assert_eq!(app.command, automation);
    }
}
