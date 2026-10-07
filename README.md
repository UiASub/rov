# rov
Monorepo for UiASub next generation ROV. Contains both topside and rov-side.

## Sensors and cameras

- Deepwater Exploration exploreHD USB camera
- WGWK IMX307 3MP IP camera, 1.5 mm 180° fisheye, PoE/ONVIF
- DVL A50 Doppler Velocity Log
- Bar30/Bar100 depth and pressure sensor
- VectorNav VN-100 IMU/AHRS
- Sonoptix ECHO multibeam imaging sonar

## Topside prototype

```sh
cargo run -p topside
```

Iced GUI with simulated streams, telemetry, and four-axis controls.
See [topside/README.md](topside/README.md).
