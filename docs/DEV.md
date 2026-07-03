# This markdown contains dev notes for the iDescriptor project.

## Transfer speed tests

1 MiB chunk size is always the fastest for file transfers

Whether transferring files over USB or wirelessly


### Device: iPhone 13 iOS 26 - Wired TYPE-C
remote path: /DCIM/100APPLE/IMG_0037.MP4
transport: wired
udid: $UDID


|   Chunk |       Bytes | Seconds |     MiB/s |
| ------: | ----------: | ------: | --------: |
|   4 KiB | 145,799,590 |  25.778 |      5.39 |
|  16 KiB | 145,799,590 |  11.097 |     12.53 |
|  64 KiB | 145,799,590 |   5.737 |     24.23 |
| 256 KiB | 145,799,590 |   4.029 |     34.51 |
|   1 MiB | 145,799,590 |   3.615 | **38.46** |
|   4 MiB | 145,799,590 |   3.622 |     38.39 |


### Device: iPhone 8 iOS 16 - Wired Type-c
|   Chunk |       Bytes | Seconds |     MiB/s |
| ------: | ----------: | ------: | --------: |
|   4 KiB | 134,893,219 |  19.384 |      6.64 |
|  16 KiB | 134,893,219 |   7.915 |     16.25 |
|  64 KiB | 134,893,219 |   4.706 |     27.34 |
| 256 KiB | 134,893,219 |   3.897 |     33.01 |
|   1 MiB | 134,893,219 |   3.667 |     35.08 |
|   4 MiB | 134,893,219 |   3.666 | **35.09** |



### Device: iPhone 6s iOS 15 - Wireless
Running target/debug/export_speed /DCIM/104APPLE/IMG_4048.MOV true /var/lib/lockdown/$UDID.plist 192.168.1.160 remote path: /DCIM/104APPLE/IMG_4048.MOV transport: wireless

|   Chunk |       Bytes | Seconds |     MiB/s |
| ------: | ----------: | ------: | --------: |
|   4 KiB | 134,893,219 |  75.049 |      1.71 |
|  16 KiB | 134,893,219 |  28.400 |      4.53 |
|  64 KiB | 134,893,219 |  14.447 |      8.90 |
| 256 KiB | 134,893,219 |   9.518 |     13.52 |
|   1 MiB | 134,893,219 |   8.709 | **14.77** |
|   4 MiB | 134,893,219 |   9.906 |     12.99 |
