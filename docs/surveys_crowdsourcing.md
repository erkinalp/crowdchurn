# Crowdsourcing Use Case: "Reverse Upwork" with Surveys

## Overview

The survey system can be used for **crowdsourcing work distribution** where tasks are assigned to users based on their tier/variant, and they complete work through survey responses.

## Use Cases

### 1. Pre-Purchase Task Assignment
Assign qualification tasks before allowing purchase:
```ruby
# Create a qualification survey for a specific tier
product = Link.find_by(unique_permalink: 'freelance-platform')
basic_tier = product.tiers.find_by(name: 'Basic')

qual_survey = product.surveys.create!(
  title: "Designer Qualification Test",
  base_variant_id: basic_tier.id,
  closes_at: nil, # Always available
  allow_multiple_responses: false
)

# Add task questions
qual_survey.survey_questions.create!([
  {
    question_text: "Upload your portfolio (paste URL)",
    question_type: :text_short,
    position: 0,
    required: true
  },
  {
    question_text: "Rate your Figma proficiency",
    question_type: :rating_scale,
    position: 1,
    required: true,
    settings: { min_rating: 1, max_rating: 5 }
  }
])
```

### 2. Post-Purchase Task Distribution
Distribute work to paid members based on their tier:

```ruby
# Premium tier gets access to higher-paying tasks
premium_tier = product.tiers.find_by(name: 'Premium')

task_survey = product.surveys.create!(
  title: "Logo Design Task #1234",
  description: "Design a logo for TechStartup Inc. - $50 payout",
  base_variant_id: premium_tier.id,
  closes_at: 48.hours.from_now,
  allow_multiple_responses: false # First come, first served
)

task_survey.survey_questions.create!(
  question_text: "Upload your logo design",
  question_type: :text_short,
  position: 0,
  required: true
)
```

### 3. A/B Testing Different Task Presentations

Use existing post variants to test different task descriptions:

```ruby
post = Installment.find(789)

# Create variants with different task descriptions
variant_a = post.post_variants.create!(
  name: "Standard Instructions",
  message: "Complete this survey to earn $10",
  is_control: true
)

variant_b = post.post_variants.create!(
  name: "Gamified Instructions",
  message: "🎯 Quest Available: Earn $10 by completing this survey!"
)

# Attach survey to the post (works with both variants)
survey = post.surveys.create!(
  title: "Data Labeling Task",
  closes_at: 1.week.from_now
)

# Users assigned to variant_a or variant_b see different messaging
# but complete the same underlying survey
```

## Performance Optimizations

### Batch Task Assignment

Assign tasks to thousands of users efficiently:

```ruby
# Get all users in the Premium tier
premium_subscribers = User.joins(:subscriptions)
                         .merge(Subscription.active)
                         .where(subscriptions: { link_id: product.id })
                         .distinct

# Batch assign survey/task to all eligible users
assigned_count = SurveyAssignmentService.batch_assign(
  survey: task_survey,
  users: premium_subscribers
)

puts "Assigned task to #{assigned_count} users"
```

### Finding Available Tasks for a User

Efficiently query what tasks a user can work on:

```ruby
# Get tasks available for this user based on their tiers
user = User.find(123)
subscription = user.subscriptions.active.first

assignment_service = SurveyAssignmentService.new(
  user: user,
  subscription: subscription
)

# Get all available tasks
available_tasks = assignment_service.available_surveys
# Returns surveys user hasn't completed, filtered by their variant access

# Get next single task (for sequential assignment)
next_task = assignment_service.next_available_survey

# Get tasks user is currently working on
in_progress = assignment_service.in_progress_surveys
```

### High-Volume Query Performance

The system includes optimized indexes for:
- Fast variant-based filtering
- Quick "already completed" checks
- Efficient aggregation for analytics
- Batch operations

```ruby
# This query is optimized with composite indexes:
Survey.active
      .for_variants(user_variant_ids)
      .available_for_user(user)
      .with_response_stats
      .limit(10)
```

## Workflow Examples

### Example 1: Task Marketplace

```ruby
# 1. List available tasks for user
user = current_user
service = SurveyAssignmentService.new(user: user, subscription: user.active_subscription)

available_tasks = service.available_surveys

available_tasks.each do |task|
  puts "#{task.title} - Closes: #{task.closes_at}"
end

# 2. User claims a task
task = available_tasks.first
response = task.survey_responses.create!(
  user: user,
  started_at: Time.current
)

# 3. User completes task
task.survey_questions.each do |question|
  response.survey_answers.create!(
    survey_question: question,
    text_answer: user_provided_answer
  )
end

# 4. Mark complete
response.complete! # Validates all required questions answered

# 5. Process payout (your custom logic)
if response.completed?
  PayoutService.new(response).process_payment
end
```

### Example 2: Qualification Pipeline

```ruby
# Pre-purchase: User must pass qualification
qual_survey = product.surveys.find_by(title: "Qualification Test")

# User takes qualification survey
response = qual_survey.survey_responses.create!(user: user)
# ... user answers questions ...
response.complete!

# Check if user passed (example: rating average > 3)
rating_answers = response.survey_answers.where.not(rating_value: nil)
avg_rating = rating_answers.average(:rating_value)

if avg_rating >= 3.0
  # Grant access to purchase
  user.update(qualified_for_platform: true)

  # Send invitation
  UserMailer.qualification_passed(user.id).deliver_later
else
  # User failed, perhaps allow retry
  UserMailer.qualification_failed(user.id).deliver_later
end
```

## Performance Considerations

### For High-Volume Task Distribution

1. **Use batch assignment**:
   ```ruby
   SurveyAssignmentService.batch_assign(survey: task, users: eligible_users)
   ```

2. **Preload associations**:
   ```ruby
   surveys = Survey.active
                   .includes(:survey_questions, :survey_responses)
                   .for_variants(variant_ids)
   ```

3. **Cache completed survey IDs**:
   ```ruby
   # In SurveyAssignmentService, we cache completed_survey_ids
   # to avoid N+1 queries
   ```

4. **Use counter caches**:
   ```ruby
   # response_count on surveys table is incremented automatically
   # No need to COUNT(*) every time
   ```

5. **Leverage indexes**:
   - `index_surveys_on_variant_availability` - Fast variant filtering
   - `index_survey_responses_on_user_completion` - Fast incomplete task lookup
   - `index_survey_responses_uniqueness_check` - Fast duplicate prevention

### Expected Performance

With proper indexing:
- **Task listing**: <50ms for 1000 available tasks
- **Assignment check**: <10ms per user
- **Batch assignment**: ~500 users/second
- **Analytics aggregation**: <200ms for 10,000 responses

## Integration with Payments

You can tie survey completion to payouts:

```ruby
class SurveyResponse < ApplicationRecord
  after_update :trigger_payout, if: :completed?

  def trigger_payout
    # Your payout logic here
    # Could create a Credit, Payment, etc.

    if survey.description.match(/\$(\d+)/)
      amount_cents = $1.to_i * 100

      Credit.create!(
        user: user,
        amount_cents: amount_cents,
        note: "Payment for: #{survey.title}"
      )
    end
  end
end
```

## Tips for Crowdsourcing Success

1. **Set clear closes_at times** for time-sensitive tasks
2. **Use allow_multiple_responses: false** for first-come-first-served tasks
3. **Use base_variant_id** to control who sees which tasks (tier-based)
4. **Use post_variants** to A/B test task presentation
5. **Monitor completion_rate** to optimize task clarity
6. **Use SurveyAnalyticsService** to track worker performance

## Privacy in Crowdsourcing Context

Even in crowdsourcing:
- Workers only see their own submitted work
- Platform owner (you) sees aggregated analytics
- Individual worker responses remain private

This is perfect for competitive task assignment where you don't want workers seeing each other's submissions!
