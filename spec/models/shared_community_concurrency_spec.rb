# frozen_string_literal: true

require "spec_helper"
require "timeout"

RSpec.describe Community, "shared product concurrency" do
  self.use_transactional_tests = false

  before do
    @seller = create(:user)
    @source_product = create(:product, user: @seller, community_chat_enabled: true)
    @community = create(:community, seller: @seller, resource: @source_product)
    @product = create(:product, user: @seller)
    @threads = []
    @errors = Queue.new
  end

  after do
    @threads.each do |thread|
      next if thread.join(1)

      thread.kill
      thread.join
    end
    @community.destroy!
    @product.destroy!
    @source_product.destroy!
    RefundPolicy.where(seller_id: @seller.id).delete_all
    @seller.destroy!
  end

  def in_connection(&block)
    @threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection(&block)
    rescue StandardError => error
      @errors << error
    end
    @threads.last
  end

  it "rejects selection when the last product archives the community after it was read" do
    selected = Queue.new
    resume_selection = Queue.new
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      next unless Thread.current[:selecting_shared_community]
      next unless payload[:sql].include?("FROM `communities`") && !payload[:sql].include?("FOR UPDATE")

      Thread.current[:selecting_shared_community] = false
      selected << true
      resume_selection.pop
    end

    selector = in_connection do
      Thread.current[:selecting_shared_community] = true
      Link.find(@product.id).toggle_community_chat!(true, shared_community_id: @community.external_id)
    ensure
      Thread.current[:selecting_shared_community] = false
    end
    Timeout.timeout(10) { selected.pop }

    @source_product.toggle_community_chat!(false)
    expect(@community.reload).to be_deleted
    resume_selection << true
    expect(selector.join(10)).to be_present

    expect(@errors.size).to eq(1)
    expect(@errors.pop).to be_a(Link::LinkInvalid)
    expect(@product.reload).not_to be_community_chat_enabled
    expect(@product.community_products).to be_empty
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    resume_selection << true
  end

  it "retains an association committed after the archiver established its read snapshot" do
    @source_product.update!(community_chat_enabled: false)
    snapshot_read = Queue.new
    resume_archival = Queue.new

    archiver = in_connection do
      Community.transaction do
        community = Community.find(@community.id)
        community.active_products.to_a
        snapshot_read << true
        resume_archival.pop
        community.archive_if_unused!
      end
    end
    Timeout.timeout(10) { snapshot_read.pop }

    @product.toggle_community_chat!(true, shared_community_id: @community.external_id)
    resume_archival << true
    expect(archiver.join(10)).to be_present

    expect(@errors.size).to eq(0), -> { @errors.size.times.map { @errors.pop.full_message }.join("\n") }
    expect(@community.reload).to be_alive
    expect(@product.reload.effective_community).to eq(@community)
  ensure
    resume_archival << true
  end
end
