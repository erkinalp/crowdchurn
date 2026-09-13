# frozen_string_literal: true

# Set on every web/worker process at cutover; never let a partially imported table go live.
if ENV["EMAIL_ENGAGEMENT_MIGRATION_RUN_ID"].present?
  Rails.application.config.after_initialize do
    control = EmailEngagementDynamoStore.client.get_item(
      table_name: EmailEngagementDynamoStore.table_name,
      key: EmailEngagementMigration::CONTROL_KEY,
      consistent_read: true
    ).item
    unless control && control["state"] == "released" && control["run_id"] == ENV.fetch("EMAIL_ENGAGEMENT_MIGRATION_RUN_ID")
      raise "Email engagement target has not been reconciled/released for EMAIL_ENGAGEMENT_MIGRATION_RUN_ID"
    end
  end
end
