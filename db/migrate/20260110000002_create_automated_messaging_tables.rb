# frozen_string_literal: true

class CreateAutomatedMessagingTables < ActiveRecord::Migration[7.1]
  def change
    # Message templates created by creators
    create_table :message_templates do |t|
      t.references :user, null: false, foreign_key: true # Creator
      t.references :templateable, polymorphic: true, null: false # Link or Installment
      t.string :name, null: false
      t.text :message_body, null: false, limit: 16.megabytes
      t.string :subject
      t.integer :trigger_type, null: false, default: 0
      t.json :trigger_config
      t.boolean :active, default: true, null: false
      t.integer :priority, default: 0, null: false

      t.timestamps
      t.datetime :deleted_at
    end

    add_index :message_templates, [:user_id, :deleted_at]
    add_index :message_templates, [:templateable_type, :templateable_id, :trigger_type],
              name: "index_message_templates_on_templateable_and_trigger"
    add_index :message_templates, [:trigger_type, :active, :deleted_at],
              name: "index_message_templates_on_trigger_active"

    # A/B test variants for message templates
    create_table :message_template_variants do |t|
      t.references :message_template, null: false, foreign_key: true
      t.string :variant_name, null: false
      t.text :message_body, null: false, limit: 16.megabytes
      t.string :subject
      t.integer :weight, default: 1, null: false
      t.integer :sent_count, default: 0, null: false
      t.integer :read_count, default: 0, null: false
      t.integer :reply_count, default: 0, null: false

      t.timestamps
    end

    add_index :message_template_variants, [:message_template_id, :variant_name],
              name: "index_message_template_variants_uniqueness",
              unique: true

    # Actual sent automated messages
    create_table :automated_messages do |t|
      t.references :message_template, null: false, foreign_key: true
      t.references :purchase, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true # Recipient (buyer)
      t.bigint :sender_id, null: false # Creator
      t.references :message_template_variant, null: true, foreign_key: true
      t.text :rendered_message, null: false, limit: 16.megabytes
      t.string :rendered_subject
      t.datetime :sent_at
      t.datetime :read_at
      t.boolean :buyer_replied, default: false, null: false

      t.timestamps
    end

    add_foreign_key :automated_messages, :users, column: :sender_id

    add_index :automated_messages, [:user_id, :sent_at],
              name: "index_automated_messages_on_recipient_and_sent"
    add_index :automated_messages, [:sender_id, :created_at],
              name: "index_automated_messages_on_sender_and_created"
    add_index :automated_messages, [:purchase_id, :message_template_id],
              name: "index_automated_messages_uniqueness",
              unique: true
    add_index :automated_messages, [:user_id, :read_at],
              name: "index_automated_messages_unread",
              where: "read_at IS NULL"
    add_index :automated_messages, :buyer_replied,
              where: "buyer_replied = true"

    # Buyer replies to automated messages
    create_table :automated_message_replies do |t|
      t.references :automated_message, null: false, foreign_key: true
      t.references :sender, null: false, foreign_key: { to_table: :users }
      t.references :recipient, null: false, foreign_key: { to_table: :users }
      t.text :message_body, null: false, limit: 16.megabytes
      t.datetime :read_at

      t.timestamps
    end

    add_index :automated_message_replies, [:recipient_id, :read_at],
              name: "index_automated_message_replies_unread",
              where: "read_at IS NULL"
    add_index :automated_message_replies, [:automated_message_id, :created_at],
              name: "index_automated_message_replies_on_message"
  end
end
