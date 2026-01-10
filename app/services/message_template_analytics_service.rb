# frozen_string_literal: true

# Provides analytics for message template performance
class MessageTemplateAnalyticsService
  def initialize(message_template)
    @template = message_template
  end

  def call
    {
      overview: overview_stats,
      variants: variant_performance,
      recent_messages: recent_message_stats
    }
  end

  private

  def overview_stats
    messages = @template.automated_messages

    {
      total_sent: messages.count,
      total_read: messages.read.count,
      total_replies: messages.with_replies.count,
      read_rate: calculate_rate(messages.read.count, messages.count),
      reply_rate: calculate_rate(messages.with_replies.count, messages.count),
      avg_time_to_read: average_time_to_read(messages)
    }
  end

  def variant_performance
    return [] unless @template.message_template_variants.any?

    @template.message_template_variants.map do |variant|
      {
        variant_id: variant.id,
        name: variant.variant_name,
        sent_count: variant.sent_count,
        read_count: variant.read_count,
        reply_count: variant.reply_count,
        read_rate: variant.read_rate,
        reply_rate: variant.reply_rate,
        weight: variant.weight
      }
    end
  end

  def recent_message_stats
    # Last 10 messages sent
    @template.automated_messages
             .recent
             .limit(10)
             .pluck(:id, :sent_at, :read_at, :buyer_replied)
             .map do |id, sent_at, read_at, replied|
      {
        id: id,
        sent_at: sent_at,
        read: read_at.present?,
        replied: replied
      }
    end
  end

  def average_time_to_read(messages)
    read_messages = messages.where.not(read_at: nil).where.not(sent_at: nil)

    return nil if read_messages.empty?

    times = read_messages.pluck(:sent_at, :read_at).map do |sent, read|
      read - sent
    end

    avg_seconds = times.sum / times.size
    format_duration(avg_seconds)
  end

  def calculate_rate(numerator, denominator)
    return 0 if denominator.zero?
    (numerator.to_f / denominator * 100).round(2)
  end

  def format_duration(seconds)
    if seconds < 60
      "#{seconds.round}s"
    elsif seconds < 3600
      "#{(seconds / 60).round}m"
    elsif seconds < 86400
      hours = (seconds / 3600).floor
      minutes = ((seconds % 3600) / 60).round
      "#{hours}h #{minutes}m"
    else
      days = (seconds / 86400).floor
      hours = ((seconds % 86400) / 3600).round
      "#{days}d #{hours}h"
    end
  end
end
