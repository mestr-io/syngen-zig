# MODELS.md - Slack Export Schemas

This document outlines the JSON schemas identified from real Slack export files. The synthetic generator (`syngen-zig`) must strictly adhere to these structures.

## 1. users.json
An array of User objects at the export root.

| Field | Type | Description |
|---|---|---|
| `id` | String | Slack User ID (e.g., "U02M3TMTV9B") |
| `team_id` | String | Workspace ID |
| `name` | String | Username |
| `deleted` | Boolean | Whether the user is deactivated |
| `real_name` | String | User's full name |
| `tz` | String | Timezone name |
| `tz_label` | String | Timezone display label |
| `tz_offset` | Integer | Timezone offset in seconds |
| `profile` | Object | Detailed profile info (see below) |
| `is_admin` | Boolean | |
| `is_owner` | Boolean | |
| `is_primary_owner` | Boolean | |
| `is_restricted` | Boolean | |
| `is_ultra_restricted` | Boolean | |
| `is_bot` | Boolean | |
| `is_app_user` | Boolean | |
| `updated` | Long | Unix timestamp |
| `is_email_confirmed` | Boolean | |

### Profile Object
- `title`: Job title.
- `real_name`: Full name.
- `display_name`: Chosen display name.
- `avatar_hash`: 12-char hex string.
- `email`: User email.
- `image_original`, `image_24`, `image_32`, etc.: URLs to avatar images.
- `status_text`, `status_emoji`: Current status.

## 2. channels.json
An array of Channel objects at the export root.

| Field | Type | Description |
|---|---|---|
| `id` | String | Channel ID (e.g., "C02TZQX58FJ") |
| `name` | String | Channel name (slug) |
| `created` | Long | Unix timestamp |
| `creator` | String | User ID of the creator |
| `is_archived` | Boolean | |
| `is_general` | Boolean | |
| `members` | Array[String] | List of User IDs in the channel |
| `pins` | Array[Object] | Optional list of pinned message objects |
| `topic` | Object | `{ value, creator, last_set }` |
| `purpose` | Object | `{ value, creator, last_set }` |

## 3. Message Objects
Located in `<channel_name>/YYYY-MM-DD.json`.

### Core Fields
- `user`: String (User ID).
- `type`: String (usually "message").
- `ts`: String (Decimal timestamp, e.g., "1755594129.627859").
- `text`: String (Message content with Slack markdown).
- `client_msg_id`: String (UUID).
- `team`: String (Workspace ID).
- `blocks`: Array[Object] (Rich text structure, required for modern Slack UI).
- `user_profile`: Object (Subset of user profile info).

### Threading metadata
- `thread_ts`: String (Timestamp of the parent message).
- `parent_user_id`: String (User ID of the thread parent).
- `reply_count`: Integer (Only on parent).
- `replies`: Array[Object] (List of `{ user, ts }` on parent).
- `latest_reply`: String (TS on parent).

### Optional Fields
- `files`: Array[Object] (Attachment metadata).
- `reactions`: Array[Object] (List of `{ name, users, count }`).
- `edited`: Object (Contains `user` and `ts`).
- `attachments`: Array[Object] (Link previews, unfurls).

## 4. Other Files (Reference)
- `canvases.json`: Metadata for Slack Canvases.
- `lists.json`: Metadata for Slack Lists.
- `integration_logs.json`: Bot/App installation logs.
- `huddle_transcripts.json`: Metadata for huddles.
