#!/usr/bin/ruby

require 'tmpdir'
require 'fileutils'
require 'rspec'
require 'tempfile'
require File.expand_path(File.dirname(__FILE__)) + "/../../geoserver_seeder.rb"

describe TileGenerator do

  describe "tile generation core" do
    before do
      @tile_generator = TileGenerator.new
    end

    it "bbox generation with gutter, zoom level 1, tile 256px, gutter 0px" do
      gutter_px = 0
      tile_size_px = 256
      tile_dimension = 180.0 / (2 ** 1)
      gutter_dimension = gutter_px * tile_dimension / tile_size_px;
      @tile_generator.to_bbox_with_gutter(-180, -90, tile_dimension, gutter_dimension).should eq([-180, -90, -90, 0])
    end

    it "bbox generation with gutter, zoom level 1, tile 256px, gutter 20px" do
      gutter_px = 20
      tile_size_px = 256
      tile_dimension = 180.0 / (2 ** 1)
      gutter_dimension = gutter_px * tile_dimension / tile_size_px;
      @tile_generator.to_bbox_with_gutter(-180, -90, tile_dimension, gutter_dimension).should eq([-187.03125, -97.03125, -82.96875, 7.03125])
    end

    it "zoom level 0, gutter 0" do
      tiles = [[-180, -90, 0, 90], [0, -90, 180, 90]]
      @tile_generator.generate_tiles(0, nil, 256, 0, "1.1.1").should eq(tiles)
    end

    it "zoom level 1, gutter 20" do
      tiles = [[-187.03125, -97.03125, -82.96875, 7.03125], [-187.03125, -7.03125, -82.96875, 97.03125], [-97.03125, -97.03125, 7.03125, 7.03125], [-97.03125, -7.03125, 7.03125, 97.03125], [-7.03125, -97.03125, 97.03125, 7.03125], [-7.03125, -7.03125, 97.03125, 97.03125], [82.96875, -97.03125, 187.03125, 7.03125], [82.96875, -7.03125, 187.03125, 97.03125]]
      @tile_generator.generate_tiles(1, nil, 256, 20, "1.1.1").should eq(tiles)
    end

    it "zoom level 1, gutter 0, version 1.3.0" do
      tiles = [[-97.03125, -187.03125, 7.03125, -82.96875], [-7.03125, -187.03125, 97.03125, -82.96875], [-97.03125, -97.03125, 7.03125, 7.03125], [-7.03125, -97.03125, 97.03125, 7.03125], [-97.03125, -7.03125, 7.03125, 97.03125], [-7.03125, -7.03125, 97.03125, 97.03125], [-97.03125, 82.96875, 7.03125, 187.03125], [-7.03125, 82.96875, 97.03125, 187.03125]]
      @tile_generator.generate_tiles(1, nil, 256, 20, "1.3.0").should eq(tiles)
    end

    it "total number of tiles generated, zoom level 0 to 8" do
      for i in 0..8
        tile_count = 2 * (4 ** i)
        @tile_generator.generate_tiles(i, nil, 256, 0, "1.1.1").size.should eq(tile_count)
      end
    end

  end
end

describe SquidLayerSeeder do

  describe "tile generation" do
    before do
      @opts_for_squid_layer_seeder = {
        :layer             => "imos:argo_profile_layer_map",
        :url_format        => Utils::get_url_format_from_url("LAYERS=imos%3Aargo_profile_layer_map&TRANSPARENT=TRUE&VERSION=1.1.1&FORMAT=image%2Fpng&QUERYABLE=true&EXCEPTIONS=application%2Fvnd.ogc.se_xml&SERVICE=WMS&REQUEST=GetMap&STYLES=&SRS=EPSG%3A4326&BBOX=86.484375,-3.515625,138.515625,48.515625&WIDTH=296&HEIGHT=296"),
        :version           => "1.1.1",
        :tile_size         => 256,
        :gutter_size       => 20,
        :geoserver_wms_url => "geoserver/wms",
        :thread_count      => 1,
        :dry_run           => true
      }
    end

    it "optimal number of threads" do
      # 2 tasks, 1 max threads, optimum is 1 (not zero!!)
      SquidLayerSeeder::optimal_number_of_threads(1, 2).should eq(1)

      # 2 tasks, 0 max threads, optimum is 1 (not zero!!)
      SquidLayerSeeder::optimal_number_of_threads(0, 2).should eq(1)

      # 10 tasks, 8 max threads, optimum will be 2
      SquidLayerSeeder::optimal_number_of_threads(8, 10).should eq(2)

      # 6000 tasks, 1 max threads, optimum is 1
      SquidLayerSeeder::optimal_number_of_threads(1, 6000).should eq(1)

      # 800 tasks, 10 max threads, optimum is 10
      SquidLayerSeeder::optimal_number_of_threads(10, 800).should eq(10)

      # 800 tasks, 10 max threads, optimum is 10
      SquidLayerSeeder::optimal_number_of_threads(10, 800).should eq(10)

      # 32 tasks, 8 max threads, optimum is 8
      SquidLayerSeeder::optimal_number_of_threads(8, 32).should eq(8)

      # 63 tasks, 16 max threads, optimum is 15
      SquidLayerSeeder::optimal_number_of_threads(16, 62).should eq(15)
    end

    it "zoom level 2 contains valid urls" do
      @opts_for_squid_layer_seeder[:zoom_level] = 2
      squid_layer_seeder = SquidLayerSeeder.new(@opts_for_squid_layer_seeder)

      url_list_for_layer = squid_layer_seeder.url_list()

      url_list_for_layer.size.should eq(2 * 4 ** 2)

      url_list_for_layer.should include("LAYERS=imos%3Aargo_profile_layer_map&TRANSPARENT=TRUE&VERSION=1.1.1&FORMAT=image%2Fpng&QUERYABLE=true&EXCEPTIONS=application%2Fvnd.ogc.se_xml&SERVICE=WMS&REQUEST=GetMap&STYLES=&SRS=EPSG%3A4326&BBOX=-48.515625,-93.515625,3.515625,-41.484375&WIDTH=296&HEIGHT=296")
      url_list_for_layer.should include("LAYERS=imos%3Aargo_profile_layer_map&TRANSPARENT=TRUE&VERSION=1.1.1&FORMAT=image%2Fpng&QUERYABLE=true&EXCEPTIONS=application%2Fvnd.ogc.se_xml&SERVICE=WMS&REQUEST=GetMap&STYLES=&SRS=EPSG%3A4326&BBOX=-93.515625,-48.515625,-41.484375,3.515625&WIDTH=296&HEIGHT=296")
    end

    it "zoom level 3 contains valid urls" do
      @opts_for_squid_layer_seeder[:zoom_level] = 3
      squid_layer_seeder = SquidLayerSeeder.new(@opts_for_squid_layer_seeder)

      url_list_for_layer = squid_layer_seeder.url_list()

      url_list_for_layer.size.should eq(2 * 4 ** 3)

      url_list_for_layer.should include("LAYERS=imos%3Aargo_profile_layer_map&TRANSPARENT=TRUE&VERSION=1.1.1&FORMAT=image%2Fpng&QUERYABLE=true&EXCEPTIONS=application%2Fvnd.ogc.se_xml&SERVICE=WMS&REQUEST=GetMap&STYLES=&SRS=EPSG%3A4326&BBOX=155.7421875,-46.7578125,181.7578125,-20.7421875&WIDTH=296&HEIGHT=296")
      url_list_for_layer.should include("LAYERS=imos%3Aargo_profile_layer_map&TRANSPARENT=TRUE&VERSION=1.1.1&FORMAT=image%2Fpng&QUERYABLE=true&EXCEPTIONS=application%2Fvnd.ogc.se_xml&SERVICE=WMS&REQUEST=GetMap&STYLES=&SRS=EPSG%3A4326&BBOX=88.2421875,-46.7578125,114.2578125,-20.7421875&WIDTH=296&HEIGHT=296")
    end

    it "zoom level 7 contains valid urls" do
      @opts_for_squid_layer_seeder[:zoom_level] = 7
      squid_layer_seeder = SquidLayerSeeder.new(@opts_for_squid_layer_seeder)

      url_list_for_layer = squid_layer_seeder.url_list()

      url_list_for_layer.size.should eq(2 * 4 ** 7)

      url_list_for_layer.should include("LAYERS=imos%3Aargo_profile_layer_map&TRANSPARENT=TRUE&VERSION=1.1.1&FORMAT=image%2Fpng&QUERYABLE=true&EXCEPTIONS=application%2Fvnd.ogc.se_xml&SERVICE=WMS&REQUEST=GetMap&STYLES=&SRS=EPSG%3A4326&BBOX=106.76513671875,-14.17236328125,108.39111328125,-12.54638671875&WIDTH=296&HEIGHT=296")

      url_list_for_layer.should include("LAYERS=imos%3Aargo_profile_layer_map&TRANSPARENT=TRUE&VERSION=1.1.1&FORMAT=image%2Fpng&QUERYABLE=true&EXCEPTIONS=application%2Fvnd.ogc.se_xml&SERVICE=WMS&REQUEST=GetMap&STYLES=&SRS=EPSG%3A4326&BBOX=95.51513671875,-15.57861328125,97.14111328125,-13.95263671875&WIDTH=296&HEIGHT=296")
    end

    it "zoom level 2 contains valid urls (gutter 0)" do
      @opts_for_squid_layer_seeder[:zoom_level] = 2
      @opts_for_squid_layer_seeder[:gutter_size] = 0
      @opts_for_squid_layer_seeder[:layer] = "default_bathy"
      @opts_for_squid_layer_seeder[:url_format] = Utils::get_url_format_from_url("LAYERS=default_bathy&TRANSPARENT=TRUE&VERSION=1.1.1&FORMAT=image%2Fpng&QUERYABLE=false&EXCEPTIONS=application%2Fvnd.ogc.se_xml&SERVICE=WMS&REQUEST=GetMap&STYLES=&SRS=EPSG%3A4326&BBOX=-45,45,0,90&WIDTH=256&HEIGHT=256")
      squid_layer_seeder = SquidLayerSeeder.new(@opts_for_squid_layer_seeder)

      url_list_for_layer = squid_layer_seeder.url_list()

      url_list_for_layer.size.should eq(2 * 4 ** 2)

      url_list_for_layer.should include("LAYERS=default_bathy&TRANSPARENT=TRUE&VERSION=1.1.1&FORMAT=image%2Fpng&QUERYABLE=false&EXCEPTIONS=application%2Fvnd.ogc.se_xml&SERVICE=WMS&REQUEST=GetMap&STYLES=&SRS=EPSG%3A4326&BBOX=-45,45,0,90&WIDTH=256&HEIGHT=256")
    end

  end
end
