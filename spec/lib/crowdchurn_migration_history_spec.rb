# frozen_string_literal: true

# Run without Rails or data services:
# bundle exec rspec --options /dev/null spec/lib/crowdchurn_migration_history_spec.rb
require "rspec"
require "active_record"
require "open3"

RSpec.describe "CrowdChurn migration history" do
  ROOT = File.expand_path("../..", __dir__)
  DEPLOYED_REF = "9a400430b"
  UPSTREAM_REF = "14fdf62c3"
  FORK_MIGRATIONS = %w[
    20251227130953_create_ab_testing_tables.rb
    20251231164645_add_exposure_and_conversion_tracking_to_variant_assignments.rb
    20260102201838_add_multi_currency_pricing_support.rb
    20260103211000_add_shipping_mode_to_links.rb
    20260110000000_create_surveys_tables.rb
    20260110000001_add_performance_indexes_for_crowdsourcing.rb
    20260110000002_create_automated_messaging_tables.rb
    20260113000001_add_product_installment_plan_to_variant_distribution_rules.rb
    20260113000002_create_product_experiments.rb
    20260113000003_add_recurrence_prices_to_product_experiment_variants.rb
    20260124145704_add_billing_currency_to_subscriptions.rb
    20260217000001_add_batch_billing_to_subscriptions.rb
    20261120000001_create_fund_carts_and_fund_cart_items.rb
  ].freeze
  FORK_TABLES = %w[
    post_variants variant_distribution_rules variant_assignments
    surveys survey_questions survey_question_options survey_responses survey_answers
    message_templates message_template_variants automated_messages automated_message_replies
    product_experiments product_experiment_variants product_experiment_assignments
    fund_carts fund_cart_items
  ].freeze

  def git(*arguments)
    output, error, status = Open3.capture3("git", "-C", ROOT, *arguments)
    raise error unless status.success?
    output
  end

  def schema_tables(source)
    source.scan(/^  create_table "([^"]+)"[^\n]*\n(.*?)^  end$/m).to_h
  end

  def definitions(body)
    body.lines.grep(/^    t\./).map(&:strip).sort
  end

  let(:paths) { Dir[File.join(ROOT, "db/migrate/*.rb")].sort }
  let(:names) { paths.map { |path| File.basename(path) } }
  let(:schema) { File.read(File.join(ROOT, "db/schema.rb")) }
  let(:tables) { schema_tables(schema) }
  let(:deployed_names) { git("ls-tree", "--name-only", "#{DEPLOYED_REF}:db/migrate").lines(chomp: true) }

  it "keeps every deployed filename and the original fork migration versions" do
    expect(deployed_names - names).to be_empty
    expect(FORK_MIGRATIONS - names).to be_empty
  end

  it "has no duplicate migration versions, loader names, or declared class names" do
    versions = names.map { |name| name.split("_").first }
    loader_names = names.map { |name| name.sub(/^\d+_/, "") }
    classes = paths.flat_map { |path| File.read(path).scan(/^class (\w+) < ActiveRecord::Migration/).flatten }

    [versions, loader_names, classes].each do |identities|
      expect(identities.tally.select { |_, count| count > 1 }).to be_empty
    end
  end

  it "creates presentment tables before their rounding and canonical-price alterations" do
    expect(names.index("20260630153000_create_buyer_presentments.rb"))
      .to be < names.index("20261206000011_add_rounding_delta_cents_to_charge_presentments.rb")
    expect(names.index("20261206000017_create_later_charge_presentments.rb"))
      .to be < names.index("20261206000018_add_canonical_price_cents_to_later_charge_presentments.rb")
    expect(schema[/define\(version: ([\d_]+)\)/, 1].delete("_")).to eq(names.last.split("_").first)
  end

  it "preserves historical foreign-key declarations without introducing new ones" do
    FORK_MIGRATIONS.each do |name|
      before = git("show", "#{DEPLOYED_REF}:db/migrate/#{name}")
      after = File.read(File.join(ROOT, "db/migrate", name))
      declarations = /foreign_key: (?:true|\{[^}]+\})|add_foreign_key[^\n]+/
      expect(after.scan(declarations)).to eq(before.scan(declarations)), name
    end

    (names - deployed_names).each do |name|
      source = File.read(File.join(ROOT, "db/migrate", name)).lines.reject { |line| line.lstrip.start_with?("#") }.join
      expect(source).not_to match(/add_foreign_key|foreign_key:\s*(?:true|\{)/), name
    end
  end

  it "does not introduce schema operations on the frozen users and purchases tables" do
    (names - deployed_names).each do |name|
      source = File.read(File.join(ROOT, "db/migrate", name)).lines.reject { |line| line.lstrip.start_with?("#") }.join
      operations = /(?:add_column|remove_column|rename_column|change_column(?:_null|_default)?|add_index|remove_index|add_reference|remove_reference|change_table|drop_table|rename_table)\s*(?:\(\s*)?:(?:users|purchases)\b/
      expect(source).not_to match(operations), name
      expect(source).not_to match(/ALTER\s+TABLE\s+`?(?:users|purchases)`?\b/i), name
    end
  end

  it "retains all fork tables, billing fields, and uniqueness constraints in the generated schema" do
    expect(FORK_TABLES - tables.keys).to be_empty
    expect(tables.fetch("links")).to include('t.integer "pricing_mode", default: 0, null: false', 't.integer "shipping_mode", default: 0, null: false')
    expect(tables.fetch("subscriptions")).to include('t.string "billing_currency", default: "usd", null: false', 't.datetime "batch_entitled_at"')
    expect(tables.fetch("comments")).to include('t.bigint "post_variant_id"')
    expect(tables.fetch("prices")).to include('name: "index_prices_on_link_currency_recurrence_flags_unique", unique: true')
    expect(tables.fetch("survey_responses")).to include('name: "index_survey_responses_on_survey_and_user", unique: true')
    expect(tables.fetch("automated_messages")).to include('name: "index_automated_messages_uniqueness", unique: true')
    expect(tables.fetch("variant_assignments")).to include('name: "index_variant_assignments_on_variant_and_subscription", unique: true')
    expect(tables.fetch("product_experiment_variants")).to include('t.json "recurrence_prices"')
    expect(tables.fetch("fund_carts")).to include('t.bigint "balance_subunits", default: 0, null: false')
    expect(tables.fetch("fund_carts")).to include('name: "index_fund_carts_on_link_id", unique: true')
  end

  it "keeps the frozen users and purchases definitions unchanged" do
    deployed = schema_tables(git("show", "#{DEPLOYED_REF}:db/schema.rb"))
    %w[users purchases].each do |name|
      expect(definitions(tables.fetch(name))).to eq(definitions(deployed.fetch(name))), name
    end
  end

  it "preserves every upstream table, column, and index alongside fork additions" do
    upstream = schema_tables(git("show", "#{UPSTREAM_REF}:db/schema.rb"))
    expect(upstream.keys - tables.keys).to be_empty
    upstream.each do |name, body|
      expect(definitions(body) - definitions(tables.fetch(name))).to be_empty, name
    end
  end

  it "matches the surveys reference to the existing integer base_variants primary key" do
    migration_namespace = Module.new
    path = File.join(ROOT, "db/migrate/20260110000000_create_surveys_tables.rb")
    migration_namespace.module_eval(File.read(path), path)
    migration = migration_namespace::CreateSurveysTables.new
    references = {}
    # Avoid Migration#respond_to_missing? opening a connection during mock setup.
    migration.define_singleton_method(:add_index) { |*| }
    migration.define_singleton_method(:create_table) { |*| }
    allow(migration).to receive(:create_table) do |name, &block|
      table = double("#{name} definition").as_null_object
      allow(table).to receive(:references) do |reference, **options|
        references[[name, reference]] = options
      end
      block.call(table)
    end

    migration.change

    expect(references.fetch([:surveys, :base_variant])).to include(type: :integer, foreign_key: true)
    expect(schema).to include('create_table "base_variants", id: :integer')
    expect(tables.fetch("surveys")).to include('t.integer "base_variant_id"')
    expect(schema).to include('add_foreign_key "surveys", "base_variants"')
  end
end
