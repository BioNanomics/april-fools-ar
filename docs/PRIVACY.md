# April Fools AR privacy policy

Effective date: November 22, 2026

April Fools AR is provided by **BioNanomics**, the owner of **The REFINERY**. This policy describes the iPhone and iPad app, including its beta builds. The REFINERY's website is [refineryrobotics.org](https://refineryrobotics.org/).

## Camera and LiDAR

The app uses the camera and, on supported devices, LiDAR to show the live view, detect AprilTags, reconstruct local geometry, and calculate measurements. This processing happens on your device. Camera access is controlled by your device's permission settings. The app does not record microphone audio, request photo-library access, or use GPS location.

When you start a recording, the app saves camera video and image samples, depth and confidence maps, camera calibration and poses, detected surfaces and AprilTags, measurements, bookmarks, and capture diagnostics. These files can reveal people, surroundings, and the layout of a space. Record only where you have permission and review recordings before sharing them.

## Information saved on your device

Recordings also contain the session name you enter, recording dates and times, random session identifiers, local file paths, device model and operating-system version, and app version and build information. The device model is a hardware model code, not a device serial number. Display and measurement preferences are saved locally.

The app has no user accounts, advertising, analytics SDK, or automatic upload service. BioNanomics and The REFINERY do not receive your camera feed or recordings automatically.

## Saved MP4s, playback, and sharing

When you stop and save a recording, the app automatically prepares a self-contained MP4 containing the complete saved recording, including clean camera video, original images, numeric depth, measurements, and readable YAML metadata. The original capture files are retained separately. If preparation is interrupted or fails, the original capture remains available and Play or Share can retry preparation. Older saved sessions are prepared when first opened for playback or sharing.

Play opens the saved camera video in the app's native video player without uploading it. Share uses the same saved MP4 and opens the system share sheet, where you select a destination. A normal video player shows only the camera video; the embedded data remains accessible through extraction tools. Sharing to another app, cloud drive, AirDrop recipient, or person gives that destination access to the complete recording under its own practices. BioNanomics or The REFINERY receives a recording only if you choose to send it to us.

## Storage, backups, and deletion

Original capture folders and prepared MP4 files are separate copies stored in the app's Documents folder. Small integrity records are saved alongside the MP4s. These files remain until you remove them or delete the app; prepared MP4s are not temporary cache files. Keeping both copies uses additional storage.

You can manage these files through the Files app or device file sharing. This version has no in-app deletion control. Removing an original capture folder alone does not remove its separate prepared MP4; remove both copies if you want to delete the complete local recording. Cached MP4 or ZIP exports created by earlier versions may also remain. The operating system may remove cached files, but the app does not promise a deletion schedule.

Your device or cloud backup settings may include app data. To remove the app's local recordings, preferences, and cached exports together, delete the app rather than offloading it. Copies you exported or backed up must be managed separately at those destinations. Deleting a local recording does not recall a shared copy.

## TestFlight beta testing

Apple's TestFlight service separately collects beta usage information and crash logs and shares them with the app provider. Feedback you submit through TestFlight may include screenshots and information you choose to provide. Depending on your invitation method, tester information may include your name and email address. See [Apple's TestFlight privacy notice](https://www.apple.com/legal/privacy/data/en/test-flight/) for the details. Do not include private recordings or sensitive screenshots in feedback unless you intend to share them.

## Privacy questions and updates

Use the Contact form at [refineryrobotics.org](https://refineryrobotics.org/) for privacy questions or requests about information you chose to send to BioNanomics or The REFINERY. We cannot access or delete recordings that exist only on your device or with another destination. Avoid attaching recordings to an initial inquiry unless needed.

We will update this policy when the app's data practices change. The effective date above identifies this version.
