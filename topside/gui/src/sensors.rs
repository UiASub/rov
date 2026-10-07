#[derive(Debug, Clone)]
pub struct Sample {
    pub sequence: u64,
    pub time: f32,
    pub depth: f32,
    pub pressure: f32,
    pub temperature: f32,
    pub heading: f32,
    pub accel: [f32; 3],
    pub gyro: [f32; 3],
    pub mag: [f32; 3],
    pub quaternion: [f32; 4],
    pub velocity: [f32; 3],
    pub altitude: f32,
    pub beam_ranges: [f32; 4],
}
impl Sample {
    pub fn demo(time: f32, sequence: u64) -> Self {
        let wave = (time * 0.4).sin();
        let depth = 4.2 + 0.04 * wave;
        let heading = 128.0 + 0.8 * (time * 0.2).sin();
        let half_yaw = heading.to_radians() / 2.0;
        Self {
            sequence,
            time,
            depth,
            heading,
            pressure: 101.325 + 9.81 * depth,
            temperature: 12.6 + 0.1 * wave,
            accel: [0.03 * wave, 0.02 * (time * 0.5).cos(), 9.81 + 0.01 * wave],
            gyro: [
                0.005 * wave,
                0.003 * wave,
                0.16_f32.to_radians() * (time * 0.2).cos(),
            ],
            mag: [19.8 + 0.2 * wave, -7.4, 42.1],
            quaternion: [half_yaw.cos(), 0.0, 0.0, half_yaw.sin()],
            velocity: [0.12 + 0.02 * wave, -0.03 + 0.01 * wave, 0.005 * wave],
            altitude: 2.34 + 0.02 * wave,
            beam_ranges: [2.64 + 0.02 * wave, 2.69, 2.71, 2.65 - 0.02 * wave],
        }
    }
}
