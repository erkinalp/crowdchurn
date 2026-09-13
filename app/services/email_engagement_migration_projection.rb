# frozen_string_literal: true

require "digest"
require "set"
require "time"
require_relative "email_engagement_dynamo_store"

class EmailEngagementMigrationProjection
  class InvalidSource < StandardError; end

  def initialize(installment_id)
    @pk = EmailEngagementDynamoStore.partition_key(installment_id)
    @opens = {}
    @clicks = {}
    @source_ids = {}
  end

  def add(kind, row)
    raise InvalidSource, "Unexpected installment_id" unless row.fetch("installment_id").to_s == @pk
    method = row.fetch("mailer_method")
    args = row.fetch("mailer_args")
    unless method.is_a?(String) && !method.empty? && args.is_a?(String)
      raise InvalidSource, "mailer_method and serialized mailer_args must be strings"
    end
    identity = { "mailer_method" => method, "mailer_args" => args }
    recipient = EmailEngagementDynamoStore.recipient_digest(mailer_method: method, mailer_args: args)
    times = row.fetch("#{kind}_timestamps")
    unless times.is_a?(Array) && !times.empty?
      raise InvalidSource, "Missing #{kind}_timestamps for source #{row.fetch('_id')}"
    end
    times = times.map { |time| canonical_time(time) }.uniq.sort
    count = row.fetch("#{kind}_count")
    unless count.is_a?(Integer) && count.positive? && count >= times.length
      raise InvalidSource, "Invalid #{kind}_count for source #{row.fetch('_id')}"
    end
    url = row.fetch("click_url") if kind == "click"
    state = [identity, times, count, url]
    source_key = [kind, row.fetch("_id").to_s]
    if @source_ids.key?(source_key)
      raise InvalidSource, "Source changed during read: #{source_key}" unless @source_ids[source_key] == state
      return
    end
    @source_ids[source_key] = state

    case kind
    when "open"
      entry = (@opens[recipient] ||= { identity:, histories: [] })
      history = { times: times.to_set, count: }
      return if entry[:histories].include?(history)
      entry[:histories].each do |other|
        next if (other[:times] & history[:times]).empty?
        if other[:count] > other[:times].size || count > times.size
          raise InvalidSource, "Ambiguous overlapping repeat-open histories for #{@pk}/#{recipient}; repair the frozen source, do not guess"
        end
      end
      entry[:histories] << history
    when "click"
      raise InvalidSource, "click_url must be a nonempty encoded string" unless url.is_a?(String) && !url.empty?
      key = "CLICK##{recipient}##{EmailEngagementDynamoStore.url_digest(url)}"
      entry = (@clicks[key] ||= identity.merge("click_url" => url, "click_count" => 1))
      entry["first_click_at"] = [entry["first_click_at"], times.first].compact.min
      entry["last_click_at"] = [entry["last_click_at"], times.last].compact.max
    else
      raise InvalidSource, "Unknown event kind #{kind}"
    end
  rescue KeyError, ArgumentError => error
    raise InvalidSource, error.message
  end

  def items
    result = {}
    @opens.each do |recipient, entry|
      times = entry[:histories].reduce(Set.new) { |all, history| all | history[:times] }
      repeats = entry[:histories].sum { |history| history[:count] - history[:times].size }
      result["OPEN##{recipient}"] = entry[:identity].merge(
        "open_count" => times.size + repeats, "first_open_at" => times.min, "last_open_at" => times.max
      )
    end
    @clicks.each do |key, click|
      result[key] = click.dup
      recipient = key.split("#")[1]
      identity = click.slice("mailer_method", "mailer_args")
      clicker = (result["CLICKER##{recipient}"] ||= identity.dup)
      clicker["first_click_at"] = [clicker["first_click_at"], click["first_click_at"]].compact.min
      clicker["last_click_at"] = [clicker["last_click_at"], click["last_click_at"]].compact.max
      url_key = EmailEngagementDynamoStore.url_sort_key(click["click_url"])
      url = (result[url_key] ||= { "click_url" => click["click_url"], "click_count" => 0 })
      url["click_count"] += 1
    end
    result.keys.grep(/\ACLICKER#/).each do |key|
      clicker = result.fetch(key)
      # Existing open rows already include any click-implied open recorded by Mongo.
      result[key.sub("CLICKER#", "OPEN#")] ||= clicker.slice("mailer_method", "mailer_args").merge(
        "open_count" => 1, "first_open_at" => clicker["first_click_at"], "last_open_at" => clicker["first_click_at"]
      )
    end
    result["SUMMARY"] = {
      "open_count" => result.keys.count { |key| key.start_with?("OPEN#") },
      "click_count" => result.keys.count { |key| key.start_with?("CLICKER#") },
      "click_pair_count" => @clicks.size,
    }
    result.sort.map { |key, attributes| attributes.merge("pk" => @pk, "sk" => key) }
  end

  private
    def canonical_time(value)
      time = value.is_a?(Time) ? value : Time.iso8601(value)
      # BSON dates have millisecond precision; refusing truncation avoids invented equality.
      raise InvalidSource, "Timestamp exceeds BSON millisecond precision" unless (time.to_r * 1000).denominator == 1
      time.getutc.iso8601(3)
    end
end
