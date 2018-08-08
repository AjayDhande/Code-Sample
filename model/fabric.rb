class Fabric < ActiveRecord::Base
  
  ADD_BY_ADMIN = "admin"
  ADD_BY_TAILOR = "tailor"
  APPROVE = "approve"
  PENDING = "pending"
  DRAFT = "draft"
  TAILOR = "tailor"

  attr_accessor :component_query

  mount_uploader :file, SimpleImageUploader
  mount_uploader :file_2, SimpleImageUploader
  # for fabrics components
  mount_uploader :temp_component_file, ImageResizeUploader

  scope :authenticated, -> () { (where approve: true, available: true).not_as_draft }
  scope :not_as_draft, -> () { where.not(status: "draft") }
  scope :available_fabric, -> () { (where approve: true, available: true).not_as_draft }
  scope :as_draft, -> () { where(status: "draft") }
  scope :owned_by_tailors, -> () { where(id: TailorFabric.pluck(:fabric_id)).uniq}
  scope :filter_draft_by_user_id_and_role, -> (user, user_role) { as_draft.where(add_by_user_id: user_role.eql?("tailor") ? user.tailor.id : user.id, add_by: user_role) }
  scope :default_for_3D, -> () { find_by_name("0001") }

  has_one :wash_instruction, dependent: :destroy
  has_many :tailor_fabrics, dependent: :destroy
  has_many :tailors, through: :tailor_fabrics

  belongs_to :pattern
  belongs_to :color
  belongs_to :material
  # add this association for collections shirts
  belongs_to :shirt
  
  accepts_nested_attributes_for :wash_instruction, :tailor_fabrics

  def self.get_piece query,fabric_id
    Fabric.find(fabric_id).get_display_component_file_url(query)
  end

  def self.filtered_fabrics *args
    query = set_filter_query args.first
    Fabric.where(query).order('fabrics.name ASC')
  end

  def self.pending_fabrics
    where(approve: false).not_as_draft
  end

  def price(currency = nil)
    amount = read_attribute(:price).to_f
    amount = currency.present? ? currency.convert(amount) : Currency.current_currency.convert(amount)
    "%.2f" % amount.round
  end

  def discount_price(currency = nil, user = nil)
    user = user.present? ? user : User.current
    result = read_attribute(:price).to_f
    result = 0 if result.nil?    
    if user and user.discount_rate
      rate = user.discount_rate.to_f
      result = (result - (result * (rate/100) ))
      result = currency.present? ? currency.convert(result) : Currency.current_currency.convert(result)
      result = "%.2f" % result.round
    else
      result = nil
    end        
    result
  end  

  def discount_rate
    user = User.current
    result = read_attribute(:price).to_f
    result = 0 if result.nil?    
    if user and user.discount_rate
      rate = user.discount_rate.to_f
    else
      rate = nil
    end        
    rate
  end  

  def is_add_by_admin
    add_by.eql?(Fabric::ADD_BY_ADMIN)
  end

  def is_add_by_tailor
    add_by.eql?(Fabric::ADD_BY_TAILOR)
  end

  def self.for_showcase
    authenticated
  end

  def self.approved_fabrics(params_tailor, user)
    fabric_id_array = user.tailor.fabrics.pluck(:fabric_id) if user.tailor.present?
    params_tailor.present? && fabric_id_array.present? ?  authenticated.where("id NOT IN(?)",fabric_id_array) : authenticated.where(add_by: ADD_BY_ADMIN)
  end

  def self.tailor_fabrics(params_tailor,user)
    if params_tailor.present?
      user.tailor.fabrics.not_as_draft
      # Fabric.not_as_draft.where(add_by: "tailor",add_by_user_id: user.id)
    else
      where(approve: true, add_by: "tailor").not_as_draft
    end
  end

  def is_associate_with_tailor(tailor)
    find_tailor_febric_association(tailor).present?
  end

  def find_tailor_febric_association(tailor)
    tailor_fabrics.find_by_tailor_id(tailor.id)
  end

  def get_display_component_file_url query
    file_path = display_component_file_relative_path(self, query)
    unless component_file_exist?(file_path) && self.temp_component_file_identifier.present?
      # file_path = default_fabric_components_files(query)
      
      # AP: add switch for DEV environment to pull the file from the productive server instead of local:
      if Rails.env.development?
        file_path = "http://localhost:3000/uploads/fabric/temp_component_file/#{self.id}/display_#{query}_Image#{self.name}.png" 
      else
        return nil  
      end
      
    end
    file_path
  end

  # This method returns the plain path to the file for non-fabric related components (like buttons, back details)
  def self.get_generic_file_url query
    # AP: add switch for DEV environment to pull the file from the productive server instead of local:
    if Rails.env.development?
      "http://localhost:3000/uploads/fabric/#{query}.png"
    else
      "/uploads/fabric/#{query}.png"
    end
  end

  def self.get_wash_instruction fabric_id
    find_by_id(fabric_id).try(:wash_instruction)
  end

  private

    def self.set_filter_query args
      query = " true "
      color_id = args[:color_id]
      pattern_id = args[:pattern_id]
      material_id = args[:material_id]
      finish_name = args[:finish_name]
      name = args[:name]
      color_id = nil if color_id.blank?
      pattern_id = nil if pattern_id.blank?
      material_id = nil if material_id.blank?
      finish_name = nil if finish_name.blank?
      name = nil if name.blank?

      unless color_id.nil?
        query += "AND color_id = #{color_id} "
      end

      unless pattern_id.nil? 
        query += "AND pattern_id = #{pattern_id} "
      end

      unless material_id.nil?
        query += "AND material_id = #{material_id} "
      end

      unless finish_name.nil?
        query += "AND desc_finish = '#{finish_name}'"
      end

      unless name.nil?
        query += "AND tailor_reference like '%#{name}%' "
      end
      query
    end

    def component_file_exist? file_path
      file_path = "#{(Rails.root).to_s}/public#{file_path}"
      File.exist?(file_path)
    end

    def display_component_file_relative_path fabric, query
        "/uploads/fabric/temp_component_file/#{fabric.id}/display_#{query}_Image#{fabric.name}.png"
    end

    def default_fabric_components_files(query)
      default_fabric = Fabric.default_for_3D
      file_path = display_component_file_relative_path(default_fabric, query)
      unless component_file_exist?(file_path) && default_fabric.temp_component_file_identifier.present?
        return nil
      end
      file_path
    end
end