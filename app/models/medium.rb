# Medium class
class Medium < ApplicationRecord
  include ApplicationHelper
  belongs_to :teachable, polymorphic: true
  has_many :medium_tag_joins, dependent: :destroy
  has_many :tags, through: :medium_tag_joins
  has_many :links, dependent: :destroy
  has_many :linked_media, through: :links
  has_many :editable_user_joins, as: :editable, dependent: :destroy
  has_many :editors, through: :editable_user_joins, as: :editable,
                     source: :user
  has_many :items, dependent: :destroy
  has_many :referrals, dependent: :destroy
  has_many :referenced_items, through: :referrals, source: :item
  include VideoUploader[:video]
  include ImageUploader[:screenshot]
  include PdfUploader[:manuscript]
  validates :sort, presence: { message: 'Es muss ein Typ angegeben werden.'}
  validates :external_reference_link, http_url: true,
                                      if: :external_reference_link?
  validates :teachable, presence: { message: 'Es muss eine Assoziation ' \
                                            'angegeben werden.'}
  validates :description, presence: { message: 'Es muss eine Beschreibung' \
                                               'angegeben werden.' },
                          unless: :undescribable?
  validates :editors, presence: { message: 'Es muss ein Editor ' \
                                           'angegeben werden.'}
  after_save :touch_teachable
  after_create :create_self_item

  def self.sort_enum
    %w[Kaviar Erdbeere Sesam Kiwi Reste KeksQuestion KeksQuiz]
  end

  def self.search(primary_lecture, params)
    course = Course.find_by_id(params[:course_id])
    return [] if course.nil?
    filtered = Medium.filter_media(course, params[:project])
    unless params[:lecture_id].present?
      return search_results(filtered, course, primary_lecture)
    end
    lecture = Lecture.find_by_id(params[:lecture_id].to_i)
    return [] unless course.lectures.include?(lecture)
    lecture.lecture_lesson_results(filtered)
  end

  def self.select_by_name
    Medium.includes(:teachable).all.map { |m| [m.title, m.id] }
  end

  def edited_by?(user)
    return true if editors.include?(user)
    false
  end

  def toc_to_vtt
    path = toc_path
    File.open(path, 'w+:UTF-8') do |f|
      f.write vtt_start
      proper_items_by_time.each do |i|
        f.write i.vtt_time_span
        f.write i.vtt_reference
      end
    end
    path
  end

  def references_to_vtt
    path = references_path
    File.open(path, 'w+:UTF-8') do |f|
      f.write vtt_start
      referrals_by_time.each do |r|
        f.write r.vtt_time_span
        f.write JSON.pretty_generate(r.vtt_properties) + "\n\n"
      end
    end
    path
  end

  def proper_items
    items.where.not(sort: 'self')
  end

  def proper_items_by_time
    proper_items.to_a.sort do |i, j|
      i.start_time.total_seconds <=> j.start_time.total_seconds
    end
  end

  def referrals_by_time
    referrals.to_a.sort do |r, s|
      r.start_time.total_seconds <=> s.start_time.total_seconds
    end
  end

  def manuscript_pages
    return unless manuscript.present?
    manuscript[:original].metadata["pages"]
  end

  def screenshot_url
    return unless screenshot.present?
    screenshot.url(host: host)
  end

  def video_url
    return unless video.present?
    video.url(host: host)
  end

  def video_filename
    return unless video.present?
    video.metadata['filename']
  end

  def video_size
    return unless video.present?
    video.metadata['size']
  end

  def video_resolution
    return unless video.present?
    video.metadata['resolution']
  end

  def video_duration
    return unless video.present?
    video.metadata['duration']
  end

  def video_duration_hms_string
    return unless video.present?
    TimeStamp.new(total_seconds: video_duration).hms_string
  end

  def manuscript_url
    return unless manuscript.present?
    manuscript[:original].url(host: host)
  end

  def manuscript_filename
    return unless manuscript.present?
    manuscript[:original].metadata['filename']
  end

  def manuscript_size
    return unless manuscript.present?
    manuscript[:original].metadata['size']
  end

  def manuscript_screenshot_url
    return unless manuscript.present?
    manuscript[:screenshot].url(host: host)
  end

  def video_width
    return unless video.present?
    video_resolution.split('x')[0].to_i
  end

  def video_height
    return unless video.present?
    video_resolution.split('x')[1].to_i
  end

  def video_aspect_ratio
    return unless video_height != 0 && video_width != 0
    video_width.to_f / video_height
  end

  def video_scaled_height(new_width)
    return unless video_height != 0 && video_width != 0
    (new_width.to_f / video_aspect_ratio).to_i
  end

  def caption
    return description if description.present?
    return unless sort == 'Kaviar' && teachable_sort == 'Lesson'
    teachable.section_titles
  end

  def card_header
    teachable.card_header
  end

  def card_header_teachable_path(user)
    teachable.card_header_path(user)
  end

  def card_subheader
    sort_de
  end

  def sort_de
    { 'Kaviar' => 'KaViaR', 'Sesam' => 'SeSAM',
      'KeksQuestion' => 'Keks-Frage', 'KeksQuiz' => 'Keks-Quiz',
      'Reste' => 'RestE', 'Erdbeere' => 'ErDBeere', 'Kiwi' => 'KIWi' }[sort]
  end

  def teachable_sort
    teachable.class.name
  end

  def teachable_sort_de
    { 'Course' => 'Kurs', 'Lecture' => 'Vorlesung',
      'Lesson' => 'Sitzung' }[teachable_sort]
  end

  def related_to_lecture?(lecture)
    return true if belongs_to_course?(lecture)
    return true if belongs_to_lecture?(lecture)
    return true if belongs_to_lesson?(lecture)
    false
  end

  def related_to_lectures?(lectures)
    lectures.map { |l| related_to_lecture?(l) }.include?(true)
  end

  def course
    return if teachable.nil?
    teachable.course
  end

  def lecture
    return if teachable.nil?
    teachable.lecture
  end

  def lesson
    return if teachable.nil?
    teachable.lesson
  end

  def self.filter_media(course, project)
    return Medium.order(:id) unless project.present?
    return [] unless course.available_food.include?(project)
    sort = project == 'keks' ? 'KeksQuiz' : project.capitalize
    Medium.where(sort: sort).order(:id)
  end

  def self.search_results(filtered_media, course, primary_lecture)
    course_results = filtered_media.select { |m| m.teachable == course }
    primary_results = Medium.filter_primary(filtered_media, primary_lecture)
    secondary_results = Medium.filter_secondary(filtered_media, course)
    secondary_results = secondary_results - course_results - primary_results
    course_results + primary_results + secondary_results
  end

  def self.filter_primary(filtered_media, primary_lecture)
    filtered_media.select do |m|
      m.teachable.present? && m.teachable.lecture == primary_lecture
    end
  end

  def self.filter_secondary(filtered_media, course)
    filtered_media.select do |m|
      m.teachable.present? && m.teachable.course == course
    end
  end

  def irrelevant?
    video_stream_link.blank? && video.nil? && manuscript.nil? &&
      external_reference_link.blank? && extras_link.blank?
  end

  def teachable_select
    teachable_type + '-' + teachable_id.to_s
  end

  def question_id
    return unless sort == 'KeksQuestion'
    external_reference_link.remove(DefaultSetting::KEKS_QUESTION_LINK).to_i
  end

  def question_ids
    return unless sort == 'KeksQuiz'
    external_reference_link.remove(DefaultSetting::KEKS_QUESTION_LINK)
                           .split(',').map(&:to_i)
  end

  def position
    teachable.media.where(sort: self.sort).order(:id).index(self)  + 1
  end

  def siblings
    teachable.media.where(sort: self.sort)
  end

  def compact_info
    compact_info = sort_de + '.' + teachable.compact_title
    return compact_info unless siblings.count > 1
    compact_info + '.(' + position.to_s + '/' + siblings.count.to_s + ')'
  end

  def details
    return description if description.present?
    return 'Frage ' + question_id.to_s if sort == 'KeksQuestion'
    return 'Fragen ' + question_ids.join(', ') if sort == 'KeksQuiz'
    ''
  end

  def title
    return compact_info if details.blank?
    compact_info + '.' + details
  end

  def title_for_viewers
    sort_de + ', ' + teachable.title_for_viewers + ', ' + description.to_s
  end

  scope :KeksQuestion, -> { where(sort: 'KeksQuestion') }
  scope :Kaviar, -> { where(sort: 'Kaviar') }

  def items_for_thyme
#    Rails.cache.fetch("#{cache_key}/items_for_thyme", expires_in: 2.hours) do
      locals = local_items
      local_selection = locals.map { |i| [i.local_reference, i.id] }
      external_items = (Item.includes(medium: :teachable).all - locals).select(&:link?) - items
      global_items = ((Item.includes(medium: :teachable).all - locals) -
                       external_items) - items
      external_selection = external_items.map { |i| [i.global_reference, i.id] }
      global_selection = global_items.map { |i| [i.global_reference, i.id] }
      local_selection + external_selection + global_selection
  #  end
  end

  def create_camtasia_items
    return unless video_stream_link.present?
    return unless video.present?
    return unless sort == 'Kaviar'
    puts id
    scraped_toc = CamtasiaScraper.new(video_stream_link).to_h[:toc]
    scraped_items = []
    scraped_toc.each do |t|
      mathitem = t[:text].match(/(Bem.|Satz|Anm.|Def.|Bsp.|Folgerung)/)
      secitem = t[:text].match(/§(\d+)\./)
      if mathitem.present?
        item_sort = { 'Bem.' => 'remark', 'Satz' => 'theorem',
                      'Def.' => 'definition', 'Anm.' => 'annotation',
                      'Bsp.' => 'example', 'Folgerung' => 'corollary' }[mathitem.captures.first]
        item_desc = t[:text].match(/\((.+)\)/)&.captures&.first
        item_section_nr = t[:text].match(/(\d+)\.\d+/)&.captures&.first
        item_nr = t[:text].match(/(\d+\.\d+)/)&.captures&.first
      elsif secitem.present?
        item_sort = 'section'
        item_section_nr = secitem.captures&.first
      else next
      end
      item_section = teachable.lecture.sections
                              .find { |s| s.reference_number == item_section_nr }
      item_start_time = TimeStamp.new(total_seconds: t[:start_time] / 1000.0)
      i = Item.create(sort: item_sort, start_time: item_start_time,
                  description: item_desc, section: item_section,
                  ref_number: item_nr, medium: self)
      puts i.errors
      scraped_items.push([item_start_time, item_sort, item_desc,
                          item_section_nr, item_nr])
    end
    scraped_items
  end

  private

  def undescribable?
    sort == 'Kaviar' || sort == 'KeksQuestion'
  end

  def touch_teachable
    return if teachable.nil?
    if teachable.course.present? && teachable.course.persisted?
      teachable.course.touch
    end
    optional_touches
  end

  def optional_touches
    if teachable.lecture.present? && teachable.lecture.persisted?
      teachable.lecture.touch
    end
    if teachable.lesson.present? && teachable.lesson.persisted?
      teachable.lesson.touch
    end
  end

  def toc_path
    Rails.root.join('public', 'tmp').to_s + '/toc-' + SecureRandom.hex + '.vtt'
  end

  def references_path
    Rails.root.join('public', 'tmp').to_s + '/ref-' + SecureRandom.hex + '.vtt'
  end

  def vtt_start
    "WEBVTT\n\n"
  end

  def belongs_to_course?(lecture)
    teachable_sort == 'Course' && teachable == lecture.course
  end

  def belongs_to_lecture?(lecture)
    teachable_sort == 'Lecture' && teachable == lecture
  end

  def belongs_to_lesson?(lecture)
    teachable_sort == 'Lesson' && teachable.lecture == lecture
  end

  def filter_primary(filtered_media, primary_lecture)
    filtered_media.select do |m|
      m.teachable.present? && m.teachable.lecture == primary_lecture
    end
  end

  def filter_secondary(filtered_media, course)
    filtered_media.select do |m|
      m.teachable.present? && m.teachable.course == course
    end
  end

  def create_self_item
    Item.create(sort: 'self', medium: self)
  end

  def local_items
    return teachable.items - items if teachable_type == 'Course'
    teachable.lecture.items - items
  end
end
