# frozen_string_literal: true

require_relative "20261120000001_create_fund_carts_and_fund_cart_items"

class CreateFundCartSettlementFoundation < ActiveRecord::Migration[7.2]
  def up
    CreateFundCartsAndFundCartItems.new.up
    change_table :fund_carts, bulk: true do |t|
      t.string :ledger_state, null: false, default: "legacy"
      t.datetime :ledger_activated_at
      t.json :activation_evidence
    end
    change_table :fund_cart_items, bulk: true do |t|
      t.json :purchase_options
      t.string :blocking_reason
    end

    create_table :fund_cart_funding_lots do |t|
      t.string :external_id, null: false
      t.bigint :fund_cart_id, null: false
      t.bigint :source_purchase_id, null: false
      t.bigint :beneficiary_id, null: false
      t.bigint :source_merchant_account_id, null: false
      t.string :processor, null: false
      t.string :custody_key, null: false
      t.string :source_payment_id
      t.string :source_balance_transaction_id
      t.string :reserve_reference
      t.string :state, null: false, default: "pending"
      t.string :currency, null: false
      t.integer :currency_exponent, null: false
      t.string :native_currency
      t.integer :native_currency_exponent
      t.string :canonical_currency, null: false
      t.integer :canonical_currency_exponent, null: false
      %i[gross fee tax affiliate net available reserved spent reversed debt].each do |name|
        t.decimal :"#{name}_subunits", precision: 36, scale: 0, null: false, default: 0
      end
      t.decimal :native_gross_subunits, precision: 36, scale: 0
      t.decimal :native_net_subunits, precision: 36, scale: 0
      t.json :amount_snapshot
      t.json :confirmation_evidence
      t.json :conversion_quote
      t.datetime :restricted_at
      t.datetime :confirmed_at
      t.datetime :available_at
      t.string :blocking_reason
      t.timestamps
      t.index :external_id, unique: true
      t.index :source_purchase_id, unique: true
      t.index [:fund_cart_id, :state], name: "index_fc_lots_on_cart_state"
      t.index [:processor, :source_payment_id], name: "index_fc_lots_on_payment"
    end

    create_table :fund_cart_settlements do |t|
      t.string :external_id, null: false
      t.string :operation_key, null: false
      t.bigint :fund_cart_id, null: false
      t.bigint :fund_cart_item_id, null: false
      t.bigint :active_item_id
      t.bigint :purchase_id, null: false
      t.bigint :beneficiary_id, null: false
      t.bigint :seller_id, null: false
      t.bigint :destination_merchant_account_id, null: false
      t.string :custody_key, null: false
      t.string :route, null: false
      t.string :state, null: false, default: "reserved"
      t.string :currency, null: false
      t.integer :currency_exponent, null: false
      t.decimal :amount_subunits, precision: 36, scale: 0, null: false
      t.decimal :reversed_subunits, precision: 36, scale: 0, null: false, default: 0
      t.json :quote_snapshot, null: false
      t.json :receipt
      t.string :blocking_reason
      t.datetime :settled_at
      t.datetime :fulfilled_at
      t.datetime :cancel_requested_at
      t.timestamps
      t.index :external_id, unique: true
      t.index :operation_key, unique: true
      t.index :active_item_id, unique: true
      t.index :purchase_id, unique: true
      t.index :fund_cart_id
      t.index :fund_cart_item_id
      t.index :state
    end

    create_table :fund_cart_settlement_allocations do |t|
      t.bigint :fund_cart_settlement_id, null: false
      t.bigint :fund_cart_funding_lot_id, null: false
      t.string :operation_key, null: false
      t.string :state, null: false, default: "reserved"
      t.decimal :amount_subunits, precision: 36, scale: 0, null: false
      t.decimal :reversed_subunits, precision: 36, scale: 0, null: false, default: 0
      t.json :external_references
      t.timestamps
      t.index :operation_key, unique: true
      t.index [:fund_cart_settlement_id, :fund_cart_funding_lot_id], unique: true, name: "index_fc_allocations_on_settlement_lot"
      t.index :fund_cart_funding_lot_id, name: "index_fc_allocations_on_lot"
    end

    create_table :fund_cart_settlement_operations do |t|
      t.string :operation_key, null: false
      t.bigint :fund_cart_id, null: false
      t.bigint :fund_cart_settlement_id
      t.bigint :fund_cart_funding_lot_id
      t.bigint :purchase_id
      t.bigint :refund_id
      t.bigint :dispute_id
      t.string :kind, null: false
      t.string :state, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.json :payload
      t.json :external_references
      t.string :error_code
      t.text :last_error
      t.datetime :available_at
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
      t.index :operation_key, unique: true
      t.index [:state, :available_at], name: "index_fc_operations_on_due"
      t.index :fund_cart_id
      t.index :fund_cart_settlement_id, name: "index_fc_operations_on_settlement"
      t.index :fund_cart_funding_lot_id, name: "index_fc_operations_on_lot"
      t.index :refund_id
      t.index :dispute_id
    end

    create_table :fund_cart_ledger_entries do |t|
      t.bigint :fund_cart_id, null: false
      t.bigint :fund_cart_funding_lot_id
      t.bigint :fund_cart_settlement_id
      t.bigint :fund_cart_settlement_operation_id, null: false
      t.bigint :user_id
      t.bigint :merchant_account_id
      t.bigint :reversal_of_id
      t.string :account, null: false
      t.integer :position, null: false
      t.string :currency, null: false
      t.integer :currency_exponent, null: false
      t.decimal :amount_subunits, precision: 36, scale: 0, null: false
      t.json :metadata
      t.datetime :created_at, null: false
      t.index [:fund_cart_settlement_operation_id, :position], unique: true, name: "index_fc_ledger_on_operation_position"
      t.index [:fund_cart_id, :account, :currency], name: "index_fc_ledger_on_cart_account_currency"
      t.index :fund_cart_funding_lot_id, name: "index_fc_ledger_on_lot"
      t.index :fund_cart_settlement_id, name: "index_fc_ledger_on_settlement"
      t.index :reversal_of_id
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Fund-cart settlement history must be retained for reconciliation."
  end
end
