use crate::{Source, style};
use iced::widget::canvas::{self, Frame, Geometry, Path, Stroke};
use iced::{Point, Rectangle, Renderer, Theme, mouse};

pub struct Preview {
    pub source: Source,
    pub elapsed: f32,
}
impl<Message> canvas::Program<Message> for Preview {
    type State = ();
    fn draw(
        &self,
        _: &(),
        renderer: &Renderer,
        _: &Theme,
        bounds: Rectangle,
        _: mouse::Cursor,
    ) -> Vec<Geometry> {
        let mut frame = Frame::new(renderer, bounds.size());
        let (w, h) = (bounds.width, bounds.height);
        frame.fill_rectangle(Point::ORIGIN, bounds.size(), style::BACKGROUND);
        if self.source == Source::None {
            return vec![frame.into_geometry()];
        }
        let grid = style::BORDER.scale_alpha(0.5);
        for i in 1..12 {
            let x = w * i as f32 / 12.0;
            frame.stroke(
                &Path::line(Point::new(x, 0.0), Point::new(x, h)),
                Stroke::default().with_color(grid),
            );
        }
        for i in 1..8 {
            let y = h * i as f32 / 8.0;
            frame.stroke(
                &Path::line(Point::new(0.0, y), Point::new(w, y)),
                Stroke::default().with_color(grid),
            );
        }
        let center = Point::new(w / 2.0, h / 2.0);
        let color = style::ACCENT.scale_alpha(0.65);
        if self.source == Source::Sonar {
            let origin = Point::new(w / 2.0, h * 0.90);
            let radius = (w * 0.46).min(h * 0.80);
            for ring in 1..=4 {
                let r = radius * ring as f32 / 4.0;
                let arc = Path::new(|p| {
                    for step in 0..=80 {
                        let angle = std::f32::consts::PI * (1.1 + step as f32 / 100.0);
                        let pt = Point::new(origin.x + angle.cos() * r, origin.y + angle.sin() * r);
                        if step == 0 {
                            p.move_to(pt);
                        } else {
                            p.line_to(pt);
                        }
                    }
                });
                frame.stroke(&arc, Stroke::default().with_color(color.scale_alpha(0.35)));
            }
            for i in 0..70 {
                let angle = std::f32::consts::PI * (1.1 + i as f32 / 87.5);
                let r = radius * (0.55 + 0.18 * (i as f32 * 0.32).sin());
                let pt = Point::new(origin.x + angle.cos() * r, origin.y + angle.sin() * r);
                frame.fill(&Path::circle(pt, 2.0), color);
            }
        } else {
            let radius = w.min(h) * 0.28;
            frame.stroke(
                &Path::circle(center, radius),
                Stroke::default().with_color(color.scale_alpha(0.5)),
            );
            let sweep = (self.elapsed * 0.15).sin() * w * 0.25 + center.x;
            frame.stroke(
                &Path::line(Point::new(sweep, 0.0), Point::new(sweep, h)),
                Stroke::default().with_color(color.scale_alpha(0.2)),
            );
            for (a, b) in [
                (
                    Point::new(center.x - 16.0, center.y),
                    Point::new(center.x + 16.0, center.y),
                ),
                (
                    Point::new(center.x, center.y - 16.0),
                    Point::new(center.x, center.y + 16.0),
                ),
            ] {
                frame.stroke(&Path::line(a, b), Stroke::default().with_color(color));
            }
        }
        frame.fill_text(canvas::Text {
            content: if self.source == Source::Sonar {
                "SONAR TEST PATTERN"
            } else {
                "VIDEO TEST PATTERN"
            }
            .into(),
            position: Point::new(16.0, h - 28.0),
            color,
            size: 11.0.into(),
            ..Default::default()
        });
        vec![frame.into_geometry()]
    }
}
