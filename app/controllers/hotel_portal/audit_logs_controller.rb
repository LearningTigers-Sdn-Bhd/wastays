require "csv"
require "cgi"
require "prawn"
require "prawn/table"

class HotelPortal::AuditLogsController < HotelPortal::BaseController
  def index
    @logs = current_hotel.inventory_audit_logs.includes(:room_type, :user).order(created_at: :desc)

    # Filtering
    @logs = @logs.where(room_type_id: params[:room_type_id]) if params[:room_type_id].present?
    @logs = @logs.where(action_type: params[:action_type]) if params[:action_type].present?

    if params[:start_date].present? && params[:end_date].present?
      @logs = @logs.where(created_at: params[:start_date].to_date.beginning_of_day..params[:end_date].to_date.end_of_day)
    end

    respond_to do |format|
      format.html { @logs = @logs.page(params[:page]).per(20) }
      format.csv { send_data generate_csv(@logs), filename: "audit-logs-#{Date.today}.csv" }
      format.xls do
        send_data generate_xls(@logs),
          filename: "audit-logs-#{Date.today}.xls",
          type: "application/vnd.ms-excel"
      end
      format.pdf do
        send_data generate_pdf(@logs),
          filename: "audit-logs-#{Date.today}.pdf",
          type: "application/pdf"
      end
    end
  end

  private

  def generate_csv(logs)
    attributes = %w[id action_type room_type user created_at old_value new_value]

    CSV.generate(headers: true) do |csv|
      csv << attributes

      logs.each do |log|
        csv << [
          log.id,
          log.action_type.titleize,
          log.room_type&.name || "N/A",
          log.user.name,
          log.created_at.strftime("%Y-%m-%d %H:%M:%S"),
          log.old_value.to_json,
          log.new_value.to_json
        ]
      end
    end
  end

  def generate_xls(logs)
    grouped_logs = logs.group_by(&:action_type)
    worksheets = grouped_logs.map do |action_type, grouped_rows|
      sheet_name = sheet_name_for_action_type(action_type)
      rows = []
      rows << xls_row([ "ID", "Room Type", "User", "Created At", "Old Value", "New Value" ])
      grouped_rows.each do |log|
        rows << xls_row([
          log.id,
          log.room_type&.name || "N/A",
          log.user.name,
          log.created_at.strftime("%Y-%m-%d %H:%M:%S"),
          log.old_value.to_json,
          log.new_value.to_json
        ])
      end

      %(<Worksheet ss:Name="#{CGI.escapeHTML(sheet_name)}"><Table>#{rows.join("\n")}</Table></Worksheet>)
    end.join("\n")

    <<~XML
      <?xml version="1.0"?>
      <?mso-application progid="Excel.Sheet"?>
      <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
        #{worksheets}
      </Workbook>
    XML
  end

  def generate_pdf(logs)
    pdf = Prawn::Document.new(page_size: "A4", margin: [ 32, 32, 32, 32 ])
    draw_header(pdf)
    pdf.text "Operation Audit Logs", size: 18, style: :bold
    pdf.move_down 4
    pdf.text current_hotel.name.to_s, size: 11, style: :bold
    pdf.text "Generated: #{Time.zone.now.strftime('%d %b %Y %I:%M %p')}", size: 10
    pdf.move_down 12

    rows = [ [ "Time", "User", "Action", "Details", "Value Change" ] ]
    logs.each do |log|
      rows << [
        log.created_at.strftime("%d %b %Y %I:%M %p"),
        log.user.name,
        log.action_type.titleize,
        log.display_details.to_s,
        log.display_value_change.to_s
      ]
    end

    pdf.table(rows, width: pdf.bounds.width, cell_style: { size: 8, padding: [ 5, 5, 5, 5 ] }) do
      row(0).font_style = :bold
    end

    pdf.render
  end

  def xls_row(values)
    "<Row>#{values.map { |value| %(<Cell><Data ss:Type=\"String\">#{CGI.escapeHTML(value.to_s)}</Data></Cell>) }.join}</Row>"
  end

  def draw_header(pdf)
    logo_path = Rails.root.join("app/assets/images/logo/long-logo.png")
    if File.exist?(logo_path)
      pdf.image logo_path, at: [ pdf.bounds.right - 150, pdf.cursor + 8 ], width: 140
    end
  end

  def sheet_name_for_action_type(action_type)
    humanized = action_type.to_s.titleize
    normalized = humanized.gsub(/[\\\/\?\*\[\]:]/, "-")
    normalized.first(31).presence || "Logs"
  end
end
