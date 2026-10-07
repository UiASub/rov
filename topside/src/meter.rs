use crate::style;
use iced::widget::canvas::{self, Frame, Geometry, Path, Stroke};
use iced::{Color, Point, Rectangle, Renderer, Theme, mouse};

/// Signed ranges fill from zero; positive ranges fill from their lower bound.
/// Bounds are display scales, not hardware limits.
pub struct Meter {
    pub value: f32,
    pub min: f32,
    pub max: f32,
    pub color: Color,
}
impl<Message> canvas::Program<Message> for Meter {
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
        let width = bounds.width;
        let position =
            |v: f32| (v.clamp(self.min, self.max) - self.min) / (self.max - self.min) * width;
        let zero = position(0.0);
        let value = position(self.value);
        frame.fill_rectangle(
            Point::new(0.0, 3.0),
            iced::Size::new(width, 6.0),
            style::RAISED,
        );
        frame.fill_rectangle(
            Point::new(zero.min(value), 3.0),
            iced::Size::new((value - zero).abs(), 6.0),
            self.color,
        );
        if self.min < 0.0 {
            frame.stroke(
                &Path::line(Point::new(zero, 0.0), Point::new(zero, 12.0)),
                Stroke::default().with_color(style::MUTED),
            );
        }
        vec![frame.into_geometry()]
    }
}
