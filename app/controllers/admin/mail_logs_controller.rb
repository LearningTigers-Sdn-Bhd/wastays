class Admin::MailLogsController < Admin::BaseController
  def index
    @status_counts = MailEvent.group(:status).count
    @pagy, @events = pagy(:offset, MailLogQuery.new(params).call, limit: 25)
  end
end
