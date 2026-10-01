# frozen_string_literal: true

class MailLogQuery
  def initialize(params = {}, scope: MailEvent.all)
    @params = params
    @scope = scope
  end

  def call
    events = @scope.recent_first
    events = events.where(status: @params[:status]) if MailEvent::STATUSES.include?(@params[:status])
    events = events.where(sent_at: date_range) if date_range
    events = events.where("recipients ILIKE :q OR subject ILIKE :q", q: "%#{search}%") if search.present?
    events
  end

  private

  def search
    @search ||= MailEvent.sanitize_sql_like(@params[:q].to_s.strip)
  end

  def date_range
    start_date, end_date = @params[:range].to_s.split("/", 2).map { |value| parse_date(value) }
    return unless start_date || end_date

    start_date&.beginning_of_day..end_date&.end_of_day
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
end
