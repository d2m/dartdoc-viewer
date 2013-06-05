library dartdoc_viewer;

import 'dart:html';
import 'package:web_ui/web_ui.dart';
import 'package:dartdoc_viewer/section.dart';
import 'package:dartdoc_viewer/item.dart';
import 'package:yaml/yaml.dart';

List<Section> loadData() {
  String path = "../yaml/test.yaml";
  
  HttpRequest.getString(path).then( (response) {
    var doc = loadYaml(response);
    print(doc);
    
    List<Section> sections = new List<Section>();
    for (String k in doc.keys) {
      print(k);
      List<Item> items = new List<Item>();
      for(String i in doc[k].keys) {
        print(i);
      }
    }
    
  });
}


/**
 * Function to create some dummy method data.
 */
List<Item> fetchDummyMethods() {
  List<Item> methods = new List<Item>();
  methods.add(new Item("Directory"));
  methods.add(new Item("File"));
  methods.add(new Item("Options"));
  methods.add(new Item("Path"));
  methods.add(new Item("SecureSocket"));
  
  return methods;
}

/**
 * Function to create some dummy section data.  
 */
List<Section> fetchDummySections() {
  List<Section> sections = new List<Section>();
  
  List<Item> constructors = new List<Item>();
  constructors.add(new Item("factory File(String path)"));
  constructors.add(new Item("factory File.fromPath(Path path)"));
  sections.add(new Section("Constructors", constructors));
  
  List<Item> properties = new List<Item>();
  properties.add(new Item("final Directory directory"));
  properties.add(new Item("final String path"));
  sections.add(new Section("Properties", properties));
  
  List<Item> methods = fetchDummyMethods();
  sections.add(new Section("Methods", methods));
  
  return sections;
}

void printItemName(Item item) {
  print(item.title);
}

final List<Section> dummySections = toObservable([]);
final List<Section> testYaml = toObservable([]);

main() {
  dummySections.addAll(fetchDummySections());
  loadData();
  //testYaml.addAll(loadData());
}