require 'image_processing/mini_magick'

# PdfUploader Class
class PdfUploader < Shrine
  # shrine plugins
  plugin :add_metadata
  plugin :determine_mime_type
  plugin :validation_helpers
  plugin :processing
  plugin :versions
  plugin :delete_raw
  plugin :pretty_location

  # extract metadata from uploaded pdf:
  # - number of pages
  # - named destinations
  # - bookmarks with details (created by mampf.sty LATeX package)
  add_metadata do |io, context|
    # no metadata extraction for the screenshot which is generated during
    # storing
    unless context[:action] == :store && context[:version] == :screenshot
      Shrine.with_file(io) do |file|
        temp_file = Tempfile.new
        cmd = "pdftk #{file.path} dump_data_utf8 output #{temp_file.path}"
        exit_status = system(cmd)
        unless exit_status
          return { 'pages' => nil, 'destinations' => nil, 'bookmarks' => nil }
        end
        meta = File.read(temp_file)
        # extract number of pages from pdftk output
        pages = /NumberOfPages: (\d*)/.match(meta)[1].to_i
        # extract lines that correspond to MaMpf-Label entries from LaTEX
        # package mampf.sty
        bookmarks = meta.scan(/BookmarkTitle: MaMpf-Label\|(.*?)\n/).flatten
        result = []
        bookmarks.each do |b|
          # extract bookmark data
          # line may look like this:
          # defn:erster-Tag-der-Schoepfung|Definition|1.1|Erster Tag|1
          data = /(.*?)\|(.*?)\|(.*?)\|(.*?)\|(.*)/.match(b)
          result.push('destination' => data[1], 'sort' => data[2],
                      'label' => data[3], 'description' => data[4],
                      'page' => data[5])
        end
        # extract named destinations using the origami gem
        # (there may be named destinations not created by the mampf LATeX
        # which would overlooked if we were to take
        # result.map { |b| b.destination }
        # instead
        pdf = Origami::PDF.read(file.path)
        if pdf.present?
          destinations = []
          pdf.each_named_dest do |d|
            # enforce UTF-8, otherwise there are problems
            destinations.push(d.value.force_encoding('UTF-8'))
          end
          # reject named destinations including spaces or "."
          # or the generic "Doc-Start" destination
          destinations.reject! do |d|
            d.include?(' ') || d.include?('.') || d == 'Doc-Start'
          end
        end
        { 'pages' => pages,
          'destinations' => destinations,
          'bookmarks' => result }
      end
    end
  end

  Attacher.validate do
    validate_mime_type_inclusion %w[application/pdf],
                                 message: 'falscher MIME-Typ'
  end

  # extract a screenshot from pdf and store it beside the pdf
  process(:store) do |io, context|
    original = io.download
    screenshot = ImageProcessing::MiniMagick.source(original).loader(page: 0)
                                            .convert('png')
                                            .resize_to_limit!(400, 565)
    original.close!
    { original: io, screenshot: screenshot }
  end
end
