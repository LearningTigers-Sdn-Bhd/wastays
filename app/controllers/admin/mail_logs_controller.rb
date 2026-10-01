class Admin::MailLogsController < Admin::BaseController
  def index
    @status_counts = MailEvent.where(sent_at: 24.hours.ago..).group(:status).count
    @pagy, @events = pagy(:offset, MailLogQuery.new(params).call, limit: 25)
  end
end
