---
title: "Visual Feedback"
subtitle: "Menu bar icon changes color. Audio level indicator shows input. Cursor indicator near your caret while recording."
description: "VocaMac provides clear visual feedback during recording with a color-changing menu bar icon, real-time audio level indicator, and an optional floating cursor indicator."
keywords: "recording indicator macOS, visual feedback dictation, menu bar recording icon, cursor indicator voice typing, audio level meter mac, recording status indicator"
icon: "📊"
---

## Always Know What's Happening

Voice dictation works best when you have complete clarity about your recording state. VocaMac provides three layers of visual feedback so you're never uncertain about whether you're recording, what your audio input looks like, or exactly where your text will appear.

## Menu Bar Icon

![VocaMac menu bar in idle state](/screenshots/menu-bar-idle.png)
![VocaMac menu bar while recording](/screenshots/menu-bar-recording.png)

The VocaMac menu bar icon is your primary indicator of recording status. It changes color instantly to show what's happening:

- **Blue (idle)**: VocaMac is running and ready to use. No recording is active. This is the default state when you're not speaking.
- **Green (recording)**: You are actively recording. Audio is flowing into the microphone and will be transcribed when you stop. This provides instant visual confirmation that your hotkey press was recognized.
- **Red (error)**: A problem occurred during transcription, audio capture, or model processing. The error message appears in the popover panel with details on how to resolve it.

These color changes happen instantly. The moment you press your activation hotkey, the icon turns green. The moment you release, it returns to blue. This immediate feedback eliminates the guesswork that plagues other voice apps.

## Real-Time Audio Level Indicator

![VocaMac popover panel showing status and audio level](/screenshots/popover-panel.png)

The popover panel displays a live audio level meter while you're recording. This horizontal bar shows your microphone's input volume in real time, helping you understand whether you're speaking loudly enough, too softly, or at an ideal level.

The audio level indicator serves multiple purposes:

- **Confidence building**: see your voice being captured as you speak
- **Troubleshooting**: if levels are flat or minimal, your microphone may not be working or properly configured
- **Microphone testing**: adjust your distance from the mic or speak louder if levels are consistently low
- **Acoustic feedback**: understand how your environment is affecting audio quality

The meter updates continuously while recording and disappears when you finish. No guessing games with your input levels.

## Floating Cursor Indicator

![VocaMac cursor indicator near text caret during recording](/screenshots/cursor-indicator.png)

VocaMac can optionally display a small floating microphone icon that appears near your text cursor while you're recording. This is especially useful when working across multiple windows, fullscreen apps, or when your menu bar is hidden.

The cursor indicator provides:

- **Context awareness**: you can see exactly where your text will be inserted, even when the menu bar isn't visible
- **Window-specific confirmation**: in applications with multiple text fields, it shows which field is active for dictation
- **Minimal distraction**: the icon is small and subtle, placed just below your cursor position

You can enable or disable the cursor indicator anytime in **Settings → General → Visual Feedback → Show Cursor Indicator**. Some users love it for extra reassurance. Others prefer the menu bar icon alone. The choice is yours.

## Why Visual Feedback Matters

Voice dictation introduces a layer of abstraction between you and your text input. Unlike typing, where you see each keystroke appear instantly, dictation requires a round trip: speak, process, transcribe, insert. Without clear visual feedback, you're flying blind.

Studies on speech interfaces show that users feel significantly more confident and make fewer corrections when they receive immediate visual confirmation of recording state. The three-layer feedback system in VocaMac addresses this:

- **Menu bar icon**: global, always visible status
- **Audio level**: real-time proof that your voice is being captured
- **Cursor indicator**: contextual placement of your output

Together, these create a complete feedback loop that matches the directness of keyboard input.

## Combining Feedback Sources

Many users rely on all three feedback sources simultaneously. While recording in a fullscreen text editor:

1. You glance at the menu bar and see the icon is green (recording is active)
2. You see the audio level meter climbing in the popover (your voice is being captured)
3. You see the cursor indicator blinking near your text field (this is where your words will appear)

Each feedback source reinforces the others, creating absolute confidence that your dictation is working as expected.

If any of these signals is missing or unclear, you can adjust settings or check your audio configuration. VocaMac's feedback system makes troubleshooting straightforward.

## Accessibility and Visibility

The color-coded menu bar icon uses high-contrast colors (blue, green, red) that are easily distinguishable. The audio level meter provides both visual and spatial feedback. Together with the cursor indicator, VocaMac ensures that visual feedback is clear and actionable for all users.

You control what's visible and when. Customize your feedback experience in Settings to match your preferences and workflow.
