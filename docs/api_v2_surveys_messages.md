# CrowdChurn API v2 - Surveys & Automated Messages

## Overview

RESTful JSON API for programmatically managing surveys and automated messages for crowdsourcing workflows. Use this API to:
- Create and manage surveys for task assignment
- Submit and verify survey responses
- Set up automated message templates
- Integrate verifiers, sanitizers, and quality control tools

## Authentication

All API requests require Bearer token authentication:

```http
Authorization: Bearer YOUR_API_TOKEN
```

Get your API token from your user account settings.

---

## Surveys API

### List Surveys

```http
GET /api/v2/surveys
```

**Response:**
```json
{
  "surveys": [
    {
      "id": "survey_abc123",
      "title": "Logo Design Task #1234",
      "description": "Design a logo for TechStartup Inc.",
      "anonymous": false,
      "allow_multiple_responses": false,
      "closes_at": "2026-01-15T00:00:00Z",
      "active": true,
      "response_count": 45,
      "completion_rate": 82.5,
      "created_at": "2026-01-10T10:00:00Z",
      "updated_at": "2026-01-10T11:00:00Z"
    }
  ],
  "meta": {
    "current_page": 1,
    "total_pages": 3,
    "total_count": 45,
    "per_page": 20
  }
}
```

### Create Survey

```http
POST /api/v2/surveys
```

**Parameters:**
```json
{
  "link_id": "link_xyz789",
  "survey": {
    "title": "Data Labeling Task",
    "description": "Label images for ML training",
    "anonymous": false,
    "allow_multiple_responses": false,
    "closes_at": "2026-01-20T00:00:00Z",
    "base_variant_id": 123,
    "survey_questions_attributes": [
      {
        "question_text": "Upload labeled image URL",
        "question_type": "text_short",
        "position": 0,
        "required": true
      },
      {
        "question_text": "Confidence level",
        "question_type": "rating_scale",
        "position": 1,
        "required": true,
        "settings": {
          "min_rating": 1,
          "max_rating": 5
        }
      }
    ]
  }
}
```

### Get Survey with Questions

```http
GET /api/v2/surveys/:id
```

**Response:**
```json
{
  "survey": {
    "id": "survey_abc123",
    "title": "Data Labeling Task",
    "questions": [
      {
        "id": "question_def456",
        "question_text": "Upload labeled image URL",
        "question_type": "text_short",
        "position": 0,
        "required": true,
        "settings": {},
        "options": []
      }
    ]
  }
}
```

### Get Survey Analytics

```http
GET /api/v2/surveys/:id/analytics
```

**Response:**
```json
{
  "survey_id": "survey_abc123",
  "analytics": {
    "overview": {
      "total_responses": 100,
      "completed_responses": 85,
      "in_progress": 15,
      "completion_rate": 85.0,
      "average_time_to_complete": "3m 24s"
    },
    "questions": [
      {
        "id": "question_def456",
        "question": "How satisfied are you?",
        "type": "rating_scale",
        "required": true,
        "stats": {
          "count": 85,
          "average": 4.2,
          "min": 1,
          "max": 5,
          "distribution": {
            "5": 45,
            "4": 25,
            "3": 10,
            "2": 3,
            "1": 2
          }
        }
      }
    ]
  }
}
```

### Get Survey Responses

```http
GET /api/v2/surveys/:id/responses
```

**Response:**
```json
{
  "responses": [
    {
      "id": "response_ghi789",
      "user_id": "user_jkl012",
      "started_at": "2026-01-10T10:00:00Z",
      "completed_at": "2026-01-10T10:05:00Z",
      "completed": true,
      "answers": [
        {
          "question_id": "question_def456",
          "text_answer": "https://example.com/labeled-image.png",
          "option_id": null,
          "rating_value": null
        }
      ]
    }
  ],
  "meta": {
    "current_page": 1,
    "total_pages": 5,
    "total_count": 85
  }
}
```

---

## Survey Responses API

### Submit Survey Response

```http
POST /api/v2/surveys/:survey_id/responses
```

**Parameters:**
```json
{
  "answers": [
    {
      "question_id": "question_def456",
      "text_answer": "https://example.com/my-work.png"
    },
    {
      "question_id": "question_abc123",
      "rating_value": 5
    }
  ],
  "complete": true
}
```

**Response:**
```json
{
  "response": {
    "id": "response_xyz456",
    "survey_id": "survey_abc123",
    "started_at": "2026-01-10T11:00:00Z",
    "completed_at": "2026-01-10T11:05:00Z",
    "completed": true
  },
  "message": "Survey completed"
}
```

### Update Response (Add More Answers)

```http
PATCH /api/v2/surveys/:survey_id/responses/:id
```

---

## Message Templates API

### List Templates

```http
GET /api/v2/message_templates
```

### Create Template

```http
POST /api/v2/message_templates
```

**Parameters:**
```json
{
  "link_id": "link_xyz789",
  "message_template": {
    "name": "Task Assignment Welcome",
    "trigger_type": "immediate_purchase",
    "subject": "Your task is ready, {name}!",
    "message_body": "Hey {name}!\n\nYou've been assigned to {product}.\n\nPlease complete the survey within 48 hours.\n\n- {creator}",
    "active": true,
    "priority": 0
  }
}
```

### Get Template Analytics

```http
GET /api/v2/message_templates/:id/analytics
```

**Response:**
```json
{
  "template_id": "template_abc123",
  "analytics": {
    "overview": {
      "total_sent": 500,
      "total_read": 425,
      "total_replies": 85,
      "read_rate": 85.0,
      "reply_rate": 17.0,
      "avg_time_to_read": "2h 15m"
    },
    "variants": [
      {
        "variant_id": 1,
        "name": "Casual",
        "sent_count": 250,
        "read_count": 220,
        "reply_count": 50,
        "read_rate": 88.0,
        "reply_rate": 20.0
      }
    ]
  }
}
```

### Preview Rendered Message

```http
POST /api/v2/message_templates/:id/preview
```

**Parameters:**
```json
{
  "purchase_id": "purchase_xyz789"
}
```

**Response:**
```json
{
  "template_id": "template_abc123",
  "variant_used": "Casual",
  "rendered_subject": "Your task is ready, Sarah!",
  "rendered_body": "Hey Sarah!\n\nYou've been assigned to Logo Design Task.\n\nPlease complete the survey within 48 hours.\n\n- John"
}
```

---

## Automated Messages API

### Get Inbox

```http
GET /api/v2/automated_messages?type=received
GET /api/v2/automated_messages?type=sent
```

### Get Message with Thread

```http
GET /api/v2/automated_messages/:id
```

**Response:**
```json
{
  "message": {
    "id": "message_abc123",
    "sender_id": "user_seller",
    "sender_name": "John Seller",
    "recipient_id": "user_buyer",
    "recipient_name": "Sarah Buyer",
    "subject": "Your task is ready, Sarah!",
    "message": "Hey Sarah!\n\nYou've been assigned...",
    "sent_at": "2026-01-10T10:00:00Z",
    "read_at": "2026-01-10T10:15:00Z",
    "buyer_replied": true,
    "template_id": "template_abc123",
    "template_name": "Task Assignment Welcome",
    "thread": [
      {
        "id": 1,
        "sender_id": "user_buyer",
        "sender_name": "Sarah Buyer",
        "recipient_id": "user_seller",
        "message_body": "Thanks! I'll get started.",
        "created_at": "2026-01-10T10:20:00Z",
        "read_at": "2026-01-10T10:25:00Z"
      }
    ]
  }
}
```

### Send Reply

```http
POST /api/v2/automated_messages/:id/reply
```

**Parameters:**
```json
{
  "message_body": "Thanks for the update!"
}
```

---

## Crowdsourcing Use Case Examples

### Example 1: Task Assignment Workflow

```python
import requests

API_URL = "https://api.crowdchurn.com/api/v2"
API_TOKEN = "your_api_token"
headers = {"Authorization": f"Bearer {API_TOKEN}"}

# 1. Create survey for task
survey = requests.post(f"{API_URL}/surveys", headers=headers, json={
    "link_id": "premium_tier",
    "survey": {
        "title": "Image Labeling Batch #42",
        "closes_at": "2026-01-12T00:00:00Z",
        "survey_questions_attributes": [
            {
                "question_text": "Upload labeled image URL",
                "question_type": "text_short",
                "required": True
            }
        ]
    }
}).json()

survey_id = survey["survey"]["id"]

# 2. Set up automated welcome message
template = requests.post(f"{API_URL}/message_templates", headers=headers, json={
    "link_id": "premium_tier",
    "message_template": {
        "name": "Task Welcome",
        "trigger_type": "immediate_purchase",
        "message_body": "Hey {name}! Your task: {product}. Complete survey: {survey_url}",
        "active": True
    }
}).json()

# 3. Check responses programmatically
responses = requests.get(
    f"{API_URL}/surveys/{survey_id}/responses",
    headers=headers
).json()

# 4. Verify and validate responses
for response in responses["responses"]:
    if response["completed"]:
        # Run your verifier/sanitizer
        is_valid = verify_response(response)

        if is_valid:
            # Send approval message
            purchase_id = response["user_id"]  # Get from response
            send_approval(purchase_id)
```

### Example 2: Quality Control with Response Verification

```python
# Fetch all responses
responses = requests.get(
    f"{API_URL}/surveys/{survey_id}/responses",
    headers=headers,
    params={"page": 1}
).json()

# Run automated quality checks
for response in responses["responses"]:
    answers = response["answers"]

    # Check image URL validity
    image_url = next(a["text_answer"] for a in answers if a["question_id"] == image_question_id)

    if validate_image_url(image_url):
        # Approve and pay
        approve_task(response["user_id"])
    else:
        # Request revision via automated message
        send_revision_request(response["user_id"])
```

### Example 3: A/B Testing Task Instructions

```python
# Create template with variants
template = requests.post(f"{API_URL}/message_templates", headers=headers, json={
    "link_id": "task_pool",
    "message_template": {
        "name": "Task Instructions A/B Test",
        "trigger_type": "immediate_purchase",
        "message_body": "Default",
        "message_template_variants_attributes": [
            {
                "variant_name": "Detailed",
                "message_body": "Complete these 5 steps carefully: 1...",
                "weight": 1
            },
            {
                "variant_name": "Brief",
                "message_body": "Label images quickly!",
                "weight": 1
            }
        ]
    }
}).json()

# Check which variant performs better
analytics = requests.get(
    f"{API_URL}/message_templates/{template['template']['id']}/analytics",
    headers=headers
).json()

# Find best performing variant
best_variant = max(
    analytics["analytics"]["variants"],
    key=lambda v: v["reply_rate"]
)
print(f"Best variant: {best_variant['name']} with {best_variant['reply_rate']}% reply rate")
```

---

## Rate Limiting

- 1000 requests per hour per API token
- Burst limit: 50 requests per minute

## Webhooks (Coming Soon)

Subscribe to events:
- `survey.response.completed`
- `message.replied`
- `survey.closed`
