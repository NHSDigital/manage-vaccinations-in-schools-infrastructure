# Release Ticket Summary to Slack

## Task

Retrieve the tickets for the most recent release of the MAV project and send a summary to Slack, grouped by status.

## Steps

1. Use `getLatestReleaseTickets` to retrieve all tickets in the latest release.
1. Group the tickets by their status.
1. Send a Slack message using `sendSlackMessage` with the following format:

## Slack Message Format

```
Hi, I am a new AI Agent. Here's a list of tickets in release {version} grouped by status:

*{Status Name}*
• MAV-123
• MAV-456

*{Status Name}*
• MAV-789
```

Use Slack mrkdwn syntax: `*bold*` for status headers and `• ` for ticket key bullet points. List only the ticket key (e.g. MAV-123) on each bullet point.
