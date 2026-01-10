# Two-Way Messaging Flow

## How Replies Work

### 1. Seller Sends Automated Message
```ruby
# Triggered automatically when user purchases
AutomatedMessage.create!(
  message_template: welcome_template,
  purchase: purchase,
  user: buyer,
  sender: seller,
  rendered_message: "Hey Sarah! Thanks for joining Premium Tier...",
  sent_at: Time.current
)
# Buyer receives notification
```

### 2. Buyer Replies
```ruby
# Buyer clicks "Reply" in their inbox
# Creates a standard user-to-seller message
BuyerReply.create!(
  automated_message: original_message,
  sender: buyer,
  recipient: seller,
  message_body: "Thanks! I'm excited to be here!"
)

# Mark the automated message as replied to
original_message.mark_buyer_replied!
# Updates analytics: reply_count incremented
```

### 3. Seller Receives Reply
```ruby
# Seller sees in their inbox:
# - Original automated message they sent
# - Buyer's reply
# - Can respond manually from there

# This becomes a normal conversation thread
# Seller can reply manually (not automated)
```

### 4. Analytics Tracking

The system tracks:
- **Send rate**: How many automated messages sent
- **Read rate**: What % of recipients opened the message
- **Reply rate**: What % replied to the automated message
- **A/B variant performance**: Which message variations get most replies

```ruby
analytics = MessageTemplateAnalyticsService.new(template).call

# Returns:
{
  total_sent: 500,
  total_read: 425,
  total_replies: 85,
  read_rate: 85.0,
  reply_rate: 17.0,  # 85/500 = 17% replied!
  variants: [
    {
      name: "Casual",
      sent: 250,
      replies: 50,
      reply_rate: 20.0  # Casual tone performs better!
    },
    {
      name: "Professional",
      sent: 250,
      replies: 35,
      reply_rate: 14.0
    }
  ]
}
```

## Reply Notifications

### For Buyers
When automated message arrives:
```
📧 New message from [Seller Name]
"Hey Sarah! Thanks for joining Premium..."
[Reply] [Mark as Read]
```

### For Sellers
When buyer replies:
```
💬 Sarah replied to your automated message
Original: "Hey Sarah! Thanks for joining Premium..."
Reply: "Thanks! I'm excited to be here!"
[Respond]
```

## Preventing Reply Spam

Optional rate limiting:
```ruby
# Limit buyers to 1 reply per automated message
class AutomatedMessage
  def can_reply?(user)
    return false if buyer_replied? # Already replied once
    user == self.user # Must be the recipient
  end
end
```

## Integration Example

```ruby
# In buyer's inbox view
<% @automated_messages.each do |msg| %>
  <div class="auto-message">
    <strong><%= msg.sender.name %></strong>
    <p><%= msg.rendered_message %></p>

    <% if msg.can_reply?(current_user) %>
      <%= button_to "Reply", reply_automated_message_path(msg) %>
    <% elsif msg.buyer_replied? %>
      <em>✓ You replied to this message</em>
    <% end %>
  </div>
<% end %>
```

## Privacy Note

> [!NOTE]
> Replies are **private** between buyer and seller
>
> - Other buyers don't see replies
> - Replies don't appear in public comments
> - Each conversation is 1-on-1

## Use Cases

### Use Case 1: Engagement Recovery
```ruby
# Template: "Hey {name}, noticed you haven't visited in a while..."
# Buyer replies: "I've been busy but I'm back now!"
# Seller responds personally: "Great to hear! Here's what you missed..."
```

### Use Case 2: Feedback Collection
```ruby
# Template: "What would you like to see next in {product}?"
# Buyer replies: "More videos on topic X!"
# Seller: "Great idea! Working on it now."
# Then seller creates content based on replies
```

### Use Case 3: Upsell Conversations
```ruby
# Template: "You're in {tier}. Want to upgrade to Premium for X benefit?"
# Buyer replies: "What's the difference?"
# Seller manually explains and closes the sale
```

## A/B Testing Reply Rates

Test which calls-to-action get more replies:

```ruby
# Variant A: Ask a question
"Hey {name}! What brought you to {product}?"
# Higher reply rate: 22%

# Variant B: Just welcome
"Hey {name}! Welcome to {product}!"
# Lower reply rate: 12%

# Conclusion: Questions drive engagement!
```
