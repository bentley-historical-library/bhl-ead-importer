BHL EAD Importer
================
Custom ArchivesSpace EAD Importer for Bentley Historical Library EADs

Basic Info
----------
This is an ArchivesSpace plug-in and can be installed following the directions on the [ArchivesSpace Plug-ins README](https://github.com/archivesspace/archivesspace/tree/master/plugins).

The plug-in adds a new importer to the application with the id "bhl_ead_xml". This is a subclass of the standard EAD importer that ships with ArchivesSpace 1.1.2.

The custom importer does the following:

  1. Creates digital object titles---when they don't exist in the EAD---based on the parent archival object's title and date(s) so that records import.
  
These customizations are specific to version 1.1.2 of ArchivesSpace and may not work with later versions.