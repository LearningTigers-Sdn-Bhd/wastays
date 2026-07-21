# Register custom MIME types for report exports.
Mime::Type.register "application/vnd.ms-excel", :xls
Mime::Type.register "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", :xlsx
