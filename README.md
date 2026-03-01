# Agora Call Recorder Service

A lightweight Flutter service package for managing **Agora RTC** cloud recording, outbound/inbound PSTN calls, and secure token handling through your backend.

This package provides an easy-to-use abstraction to:
- Fetch fresh Agora RTC tokens
- Initiate outbound PSTN calls
- Start/stop Agora cloud recording
- Communicate with your custom backend (e.g. Vercel + Flask)

Perfect for apps that need reliable voice call recording with Agora integration.

## Features

- Secure Agora RTC token generation (via backend)
- Outbound PSTN call initiation (dial phone numbers)
- Cloud recording start/stop with resource & SID tracking
- Helper methods for querying recording status
- Works with your existing Agora + Twilio backend

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  agora_call_recorder_service: ^1.0.0