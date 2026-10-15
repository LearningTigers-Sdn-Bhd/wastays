# frozen_string_literal: true

class MailLogQuery
  def initialize(params = {}, scope: MailEvent.all)
    @params = params
    @scope = scope
  end

  def call
    events = @scope.recent_first
    events = events.where(status: @params[:status]) if MailEvent::STATUSES.include?(@params[:status])
    range = LogDateRange.call(@params[:range])
    events = events.where(sent_at: range) if range
    events = events.where("recipients ILIKE :q OR subject ILIKE :q", q: "%#{search}%") if search.present?
    events
  end

  private

  def search
    @search ||= MailEvent.sanitize_sql_like(@params[:q].to_s.strip)
  end
end
