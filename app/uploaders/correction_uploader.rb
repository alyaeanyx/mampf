require 'image_processing/mini_magick'

# UserPdfUploader Class
class CorrectionUploader < Shrine
  # shrine plugins
  plugin :determine_mime_type, analyzer: :marcel
  plugin :upload_endpoint, max_size: 15*1024*1024 # 15 MB
  plugin :default_storage, cache: :submission_cache, store: :submission_store
end
