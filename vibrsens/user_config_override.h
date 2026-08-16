/*
  user_config_override.h - user configuration overrides my_user_config.h for Tasmota

  Custom build for ESP32-D0WDQ6 v1.0 (env tasmota32) with:
    USE_MPU6050, USE_MPU6050_DMP
    USE_MQTT, USE_HOME_ASSISTANT
    USE_BERRY, USE_SENDMAIL
*/

#ifndef _USER_CONFIG_OVERRIDE_H_
#define _USER_CONFIG_OVERRIDE_H_

// -- MQTT - Home Assistant Discovery -------------
#define USE_HOME_ASSISTANT                       // Enable Home Assistant Discovery Support (+12k code, +6 bytes mem)

// -- I2C sensors ---------------------------------
#define USE_MPU6050                              // Enable MPU6050 sensor (I2C address 0x68 AD0 low or 0x69 AD0 high)
  #define USE_MPU6050_DMP                        // Enable in MPU6050 to use the DMP on the chip

// -- SendMail (ESP32) ----------------------------
#define USE_SENDMAIL                             // Enable SendMail support using ESP Mail Client (+8k code, +4k mem)

#endif  // _USER_CONFIG_OVERRIDE_H_
