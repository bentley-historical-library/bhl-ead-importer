class BHLEADConverter < EADConverter

  def self.import_types(show_hidden = false)
    [
     {
       :name => "bhl_ead_xml",
       :description => "Import BHL EAD records from an XML file"
     }
    ]
  end


  def self.instance_for(type, input_file)
    if type == "bhl_ead_xml"
      self.new(input_file)
    else
      nil
    end
  end

  def self.profile
    "Convert EAD To ArchivesSpace JSONModel records"
  end

  def self.configure
    super

	with 'dao' do

=begin	
The Bentley has many EADs with <dao> tags that lack title attributes. The stock ArchivesSpace EAD Converter uses the <dao>'s title attribute as the value for the imported digital object's title, which is a required property. As a result, all of our EADs with <dao> tags failed when trying to import into ArchivesSpace. This section of the BHL EAD Converter plugin modifies the stock ArchivesSpace EAD Converter by forming a string containing the digital object's parent archival object's title and date (if both exist), or just it's title (if only the title exists), or just it's date (if only the date exists) and then using that string as the digital object's title during the EAD import process. 
=end
	
	  # new stuff...
	  title = ''
	  ancestor(:resource, :archival_object ) { |ao| title << ao.title }
	  date_label = ''
	  # WE NEED SOMETHING HERE!
	  date_label = date_label.to_s

	  # generate a display string for the digital object title based on the parent archival object's title and/or date...
	  display_string = title || ''
	  display_string += ", " if title && date_label
	  display_string += date_label if date_label
	  display_string += " Digital Object"
	 
      make :instance, {
          :instance_type => 'digital_object'
        } do |instance|
          set ancestor(:resource, :archival_object), :instances, instance
      end

      
      make :digital_object, {
        :digital_object_id => SecureRandom.uuid,
		# et voilà, a title!
		:title => display_string,
       } do |obj|
         obj.file_versions <<  {   
             :use_statement => att('role'),
             :file_uri => att('href'),
             :xlink_actuate_attribute => att('actuate'),
             :xlink_show_attribute => att('show')
         }
         set ancestor(:instance), :digital_object, obj 
      end

    end

  end
end