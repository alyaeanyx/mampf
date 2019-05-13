class Notion < ApplicationRecord
  belongs_to :tag, optional: true, touch: true
  belongs_to :aliased_tag, class_name: 'Tag', optional: true, touch: true

  validates :title, uniqueness: { scope: :locale }
  validates :title, presence: true
  validate :presence_of_tag, if: :persisted?

  after_save :touch_tag_relations

  def presence_of_tag
    return if tag || aliased_tag
    errors.add(:tag, :no_tag)
  end

  def touch_tag_relations
    tag.touch_lectures
    tag.touch_sections
    tag.touch_chapters
  end
end
