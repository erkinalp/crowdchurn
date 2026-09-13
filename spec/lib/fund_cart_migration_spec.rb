# frozen_string_literal: true

require "spec_helper"
require_relative "../../db/migrate/20260913114042_create_fund_cart_settlement_foundation"

describe CreateFundCartSettlementFoundation do
  self.use_transactional_tests = false

  before do
    [CreateFundCartsAndFundCartItems, described_class].each do |migration_class|
      allow(migration_class).to receive(:new).and_wrap_original do |constructor, *arguments|
        migration = constructor.call(*arguments)
        allow(migration).to receive(:table_name_options).and_return(table_name_prefix: prefix, table_name_suffix: "")
        migration
      end
    end
  end

  around do |example|
    ActiveRecord::Migration.suppress_messages { example.run }
  ensure
    ActiveRecord::Base.connection.tables.select { |name| name.start_with?(prefix) }.each do |name|
      ActiveRecord::Base.connection.drop_table(name)
    end
  end

  let(:connection) { ActiveRecord::Base.connection }
  let(:prefix) { "fcv_#{SecureRandom.hex(3)}_" }

  def insert_historical_cart
    connection.execute("INSERT INTO #{prefix}fund_carts (external_id, link_id, user_id, balance_subunits, currency, created_at, updated_at) VALUES ('historical', 1, 1, 2500, 'usd', NOW(), NOW())")
  end

  it "creates the prerequisite tables in fresh timestamp order and preserves them when the older migration is recorded" do
    described_class.new.migrate(:up)
    insert_historical_cart
    CreateFundCartsAndFundCartItems.new.migrate(:up)
    expect(connection.select_value("SELECT balance_subunits FROM #{prefix}fund_carts WHERE external_id = 'historical'")).to eq(2500)
    expect(connection.select_value("SELECT ledger_state FROM #{prefix}fund_carts WHERE external_id = 'historical'")).to eq("legacy")
    tables = connection.tables.select { |name| name.start_with?(prefix) }
    expect(tables.size).to eq(7)
    expect(tables.flat_map { |name| connection.foreign_keys(name) }).to be_empty
    amount = connection.columns("#{prefix}fund_cart_funding_lots").find { |column| column.name == "available_subunits" }
    expect(amount.sql_type).to eq("decimal(36,0)")
  end

  it "upgrades deployed base tables without changing historical balances or auto-activating them" do
    CreateFundCartsAndFundCartItems.new.migrate(:up)
    insert_historical_cart
    described_class.new.migrate(:up)
    expect(connection.select_value("SELECT balance_subunits FROM #{prefix}fund_carts WHERE external_id = 'historical'")).to eq(2500)
    expect(connection.select_value("SELECT ledger_state FROM #{prefix}fund_carts WHERE external_id = 'historical'")).to eq("legacy")
    CreateFundCartsAndFundCartItems.new.migrate(:down)
    expect(connection.table_exists?("#{prefix}fund_carts")).to eq(true)
    expect { described_class.new.migrate(:down) }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
