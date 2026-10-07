# Topside GUI

Run the Iced GUI prototype:

```sh
cargo run -p topside
```

All video, sonar, telemetry, and control output are simulated. No network or
joystick connection is opened. Select one, two, or four views and choose a source
for each. Sliders provide manual input; automation generates a sample command.
Disarm, neutral, and mode changes clear the command.

Debug shows simulated pressure, temperature, depth, DVL velocities and beam
ranges, IMU vectors, quaternion components, and motion requests. Signed bars
start at zero. Labeled display scales are not sensor limits. Freeze pauses the
sensor snapshot; control timing continues. Pilot and Debug share that snapshot.

Commands use normalized `[surge, sway, heave, yaw]`, with positive values meaning
forward, right, down, and clockwise viewed from above. Roll and pitch are not
commanded. The Jetson owns conversion to the MCU protocol, including quaternion
orientation setpoints; a quaternion is not the four-axis input vector.

The stream preview is a canvas test pattern. GStreamer reception, decoded-frame
rendering, the joystick helper, and Jetson communication remain to be integrated.
