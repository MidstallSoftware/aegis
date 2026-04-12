{
  aegis-ip-tools,
  gf180mcu-pdk,
  sky130-pdk,
}:
{
  terra-1 = {
    ip = aegis-ip-tools.mkIp {
      deviceName = "terra_1";
      width = 48;
      height = 64;
      tracks = 4;
      serdesCount = 4;
      bramColumnInterval = 16;
      dspColumnInterval = 24;
      clockTileCount = 2;
    };
    tapeout = {
      pdk = sky130-pdk;
      clockPeriodNs = 20;
    };
  };
  luna-1 = {
    ip = aegis-ip-tools.mkIp {
      deviceName = "luna_1";
      width = 19;
      height = 40;
      tracks = 1;
      serdesCount = 1;
      bramColumnInterval = 9;
      dspColumnInterval = 10;
      clockTileCount = 1;
    };
    tapeout = {
      pdk = gf180mcu-pdk;
      clockPeriodNs = 20;
      dieWidthUm = 3930;
      dieHeightUm = 5120;
      tilePlacementDensities.SerDesTile = 0.5;
    };
  };
}
