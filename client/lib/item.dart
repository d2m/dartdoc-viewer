// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library category_item;

import 'dart:async';
import 'dart:convert';

import 'package:dartdoc_viewer/data.dart';
import 'package:dartdoc_viewer/read_yaml.dart';
import 'package:polymer/polymer.dart';
import 'package:yaml/yaml.dart';
import 'package:dartdoc_viewer/location.dart';

// TODO(tmandel): Don't hardcode in a path if it can be avoided.
@reflectable const docsPath = 'docs/';

/**
 * Anything that holds values and can be displayed.
 */

nothing() => null;

@reflectable class Container extends Observable {
  @observable final String name;
  @observable String comment = '<span></span>';

  Container(this.name, [this.comment]);

  String toString() => "$runtimeType($name)";
}

// Wraps a comment in span element to make it a single HTML Element.
@reflectable String _wrapComment(String comment) {
  if (comment == null) comment = '';
  return '<div>$comment</div>';
}

/**
 * A [Container] that contains other [Container]s to be displayed.
 */
@reflectable class Category extends Container {

  List<Container> content = [];
  Set<String> memberNames = new Set<String>();
  int inheritedCounter = 0;
  int memberCounter = 0;

  Item memberNamed(String name, {orElse : nothing}) {
    return content.firstWhere((x) => x.name == name, orElse: orElse);
  }

  Category.forClasses(List<Map> classes, String name,
      {bool isAbstract: false}) : super(name) {
    if (classes != null) {
      classes.forEach((clazz) =>
        content.add(new Class.forPlaceholder(clazz['qualifiedName'],
            clazz['preview'])));
    }
  }

  Category.forVariables(Map variables, Map getters, Map setters)
      : super('Properties') {
    if (variables != null) {
      variables.keys.forEach((key) {
        memberNames.add(key);
        memberCounter++;
        content.add(new Variable(variables[key]));
      });
    }
    if (getters != null) {
      getters.keys.forEach((key) {
        memberNames.add(key);
        memberCounter++;
        content.add(new Variable(getters[key], isGetter: true));
      });
    }
    if (setters != null) {
      setters.keys.forEach((key) {
        memberNames.add(key);
        memberCounter++;
        content.add(new Variable(setters[key], isSetter: true));
      });
    }
  }

  /// Used to create lists of instance variables or methods by filtering.
  /// In normal usage [members] to contain all methods or all variables, rather
  /// than a mixture.
  Category.forInstanceMembers(List members, name) : super(name) {
    for (var member in members) {
      if (!member.isStatic) {
        memberNames.add(member.name);
        memberCounter++;
        if (member.isInherited) inheritedCounter++;
        content.add(member);
      }
    }
  }

  /// Used to create lists of static variables or methods by filtering.
  ///. In normal usage [members] to contain all methods or all variables, rather
  /// than a mixture.
  Category.forStaticMembers(List members, name) : super(name) {
    for (var member in members) {
      if (member.isStatic) {
        memberNames.add(member.name);
        memberCounter++;
        content.add(member);
      }
    }
  }

  Category.forFunctions(Map yaml, String name, {bool isConstructor: false,
      String className: '', bool isOperator: false, Class owner})
        : super(name) {
    if (yaml != null) {
      yaml.keys.forEach((key) {
        memberNames.add(key);
        memberCounter++;
        content.add(new Method(yaml[key], isConstructor: isConstructor,
            className: className, isOperator: isOperator, owner: owner));
      });
    }
  }

  Category.forTypedefs(Map yaml) : super ('Typedefs') {
    if (yaml != null) {
      yaml.keys.forEach((key) => content.add(new Typedef(yaml[key])));
    }
  }

  /// Adds [item] to [destination] if [item] has not yet been defined within
  /// [destination] and handles inherited comments.
  void addInheritedItem(Class clazz, Item item) {
    if (!memberNames.contains(item.name)) {
      memberCounter++;
      inheritedCounter++;
      pageIndex['${clazz.qualifiedName}.${item.name}'] = item;
      content.add(item);
    } else {
      var member = content.firstWhere((innerItem) =>
          innerItem.name == item.name);
      member.addInheritedComment(item);
    }
  }

  bool get hasNonInherited => inheritedCounter < memberCounter;

}

/**
 * A [Container] synonymous with a page.
 */
@reflectable class Item extends Container {
  /// A list of [Item]s representing the path to this [Item].
  List<Item> path = [];
  @observable final String qualifiedName;

  Item(String name, this.qualifiedName, [String comment])
      : super(name, comment);

  /// [Item]'s name with its properties properly appended.
  @observable String get decoratedName => name;

  /// Adds this [Item] to [pageIndex] and updates all necessary members.
  void addToHierarchy() {
    pageIndex[qualifiedName] = this;
  }

  /// Loads this [Item]'s data and populates all fields.
  Future load() {
    return new Future.value(this);
  }

  /// Adds the comment from [item] to [this].
  void addInheritedComment(Item item) {}

  /// Denotes whether this [Item] is inherited from another [Item] or not.
  @observable bool get isInherited => false;

  /// Creates a link for the href attribute of an [AnchorElement].
  String get linkHref => qualifiedName;

  /// The [DocsLocation] for our URI.
  DocsLocation get location => new DocsLocation(qualifiedName);

  /// The link to an anchor within a larger page, if appropriate.
  DocsLocation anchorHrefLocationFrom(aLocation) {
    var basic = aLocation;
    var parent = aLocation.parentLocation;
    if (parent.isEmpty) return parent;
    parent.anchor = parent.toHash(basic.componentNames.last);
    return parent;
  }

  DocsLocation get anchorHrefLocation => anchorHrefLocationFrom(location);

  String get anchorHref => anchorHrefLocation.withAnchor;

  bool get isLoaded => true;

  Item memberNamed(String name, {Function orElse : nothing}) => nothing();

  Item get owner => pageIndex[location.parentQualifiedName];

  Item get home => owner == null ? null : owner.home;
}

/// Sorts each inner [List] by qualified names.
@reflectable void _sort(List<List<Item>> items) {
  items.forEach((item) {
    item.sort((Item a, Item b) =>
      _compareLibraryNames(a.decoratedName, b.decoratedName));
  });
}

int _compareLibraryNames(String a, String b) {
  var aIsDart = a.startsWith("dart");
  var bIsDart = b.startsWith("dart");
  if (aIsDart == bIsDart) return a.compareTo(b);
  return aIsDart ? -1 : 1;
}


/**
 * An [Item] containing all of the [Library] and [Placeholder] objects.
 */
@reflectable class Home extends Item {

  Item get home => this;
  Home owner;

  /// All libraries being viewed from the homepage.
  List<Item> libraries = [];

  DocsLocation get anchorHrefLocation =>
      new DocsLocation(name == null ? 'home' : name);

  static _nameFromYaml(Map yaml) {
    var package = yaml['packageName'];
    return package == null ? 'home' : package;
  }

  /// The constructor parses the [yaml] input and constructs
  /// [Placeholder] objects to display before loading libraries.
  Home(Map yaml) : super(_nameFromYaml(yaml), _nameFromYaml(yaml),
      _wrapComment(yaml['introduction'])) {

    // TODO(alanknight): Fix complicated, recursive constructor.
    var libraryList = yaml['libraries'];
    var packages = new Map();
    if (isTopLevelHome) {
      libraryList.forEach((each) =>
         packages.putIfAbsent(each['packageName'], () => []).add(each));
    }

    var directLibraries = isTopLevelHome ? packages[''] : libraryList;
    for (Map library in directLibraries) {
      var libraryName = library['name'];
      var newLibrary = new Library.forPlaceholder(library);
      newLibrary.home = this;
      this.libraries.add(newLibrary);
      pageIndex[newLibrary.qualifiedName] = newLibrary;
    };
    packages.remove('');
    packages.forEach((packageName, libraries) {
      var main = libraries.firstWhere(
          (each) => each['name'] == packageName,
          orElse: () => libraries.first);
      var package = new Home({
        'libraries' : libraries,
        'packageName' : packageName
        });
      package.owner = this;
      this.libraries.add(package);
    });

    _sort([this.libraries]);
    makeMainLibrarySpecial(yaml);
    pageIndex[qualifiedName] = this;
    if (isTopLevelHome) pageIndex[''] = this;
  }

  bool get isTopLevelHome => name == 'home';

  /// Find the main library for a package and put it first in the list,
  /// and get the README for the package from it. The main library is assumed
  /// to be the one that has the same name as the package. If there is no
  /// such library, pick the first one in the (alphabetical) list and get
  /// the README from it.
  void makeMainLibrarySpecial(yaml) {
    var mainLib = libraries.firstWhere((each) => each.name == name,
        orElse: () => libraries.isEmpty ? null : libraries.first);
    if (mainLib != null) {
      libraries.remove(mainLib);
      libraries.insert(0, mainLib);
      var libs = yaml['libraries'];
      var main = libs.firstWhere((each) => each['name'] == mainLib.name);
      var intro = main['packageIntro'];
      if (intro != null && !intro.isEmpty) {
        comment = _wrapComment(intro);
      }
    }
  }

  Item memberNamed(String name, {Function orElse : nothing}) {
    return libraries.firstWhere(
        (each) => each.name == name || each.decoratedName == name,
        orElse: orElse);
  }
}

/// Runs through the member structure and creates path information.
@reflectable void buildHierarchy(Item page, Item previous) {
  if (page.path.isEmpty) {
    page.path
      ..addAll(previous.path)
      ..add(page);
  }
  page.addToHierarchy();
}

/**
 * An [Item] that is lazily loaded.
 */
@reflectable abstract class LazyItem extends Item {

  bool isLoaded = false;
  String previewComment;

  LazyItem(String qualifiedName, String name, previewComment,
      [String comment]) : super(name, qualifiedName, comment) {
    this.previewComment = previewComment;
  }

  /// Loads this [Item]'s data and populates all fields.
  Future load() {
    if (isLoaded) return new Future.value(this);
    var location = '$docsPath$qualifiedName.' + (isYaml ? 'yaml' : 'json');
    var data = retrieveFileContents(location);
    return data.then((response) {
      var yaml = isYaml ? loadYaml(response) : JSON.decode(response);
      loadValues(yaml);
      buildHierarchy(this, this);
      return new Future.value(this);
    });
  }

  /// Populates all of this [Item]'s fields.
  void loadValues(Map yaml);
}

/**
 * An [Item] that describes a single Dart library.
 */
@reflectable class Library extends LazyItem {

  Category classes;
  Category errors;
  Category typedefs;
  Category variables;
  Category functions;
  Category operators;
  Home home;

  /// Creates a [Library] placeholder object with null fields.
  Library.forPlaceholder(Map library)
    : super(
        library['qualifiedName'],
        library['name'],
        library['preview']);

  /// Normal constructor for testing.
  Library(Map yaml) : super(yaml['qualifiedName'], yaml['name'], '') {
    loadValues(yaml);
    buildHierarchy(this, this);
  }

  void addToHierarchy() {
    super.addToHierarchy();
    [classes, typedefs, errors, functions].forEach((category) {
      category.content.forEach((clazz) {
        buildHierarchy(clazz, this);
      });
    });
  }

  void loadValues(Map yaml) {
    this.comment = _wrapComment(yaml['comment']);
    var classes, exceptions, typedefs;
    var allClasses = yaml['classes'];
    if (allClasses != null) {
      classes = allClasses['class'];
      exceptions = allClasses['error'];
      typedefs = allClasses['typedef'];
    }
    this.typedefs = new Category.forTypedefs(typedefs);
    errors = new Category.forClasses(exceptions, 'Exceptions');
    this.classes = new Category.forClasses(classes, 'Classes');
    var setters, getters, methods, operators;
    var allFunctions = yaml['functions'];
    if (allFunctions != null) {
      setters = allFunctions['setters'];
      getters = allFunctions['getters'];
      methods = allFunctions['methods'];
      operators = allFunctions['operators'];
    }
    variables = new Category.forVariables(yaml['variables'], getters, setters);
    functions = new Category.forFunctions(methods, 'Functions');
    this.operators = new Category.forFunctions(operators, 'Operators',
        isOperator: true);
    _sort([this.classes.content, this.errors.content,
           this.typedefs.content, this.variables.content,
           this.functions.content, this.operators.content]);
    isLoaded = true;
  }

  String get decoratedName {
    if (isDartLibrary) {
      return name.replaceAll('-dom-', '-').replaceAll('-', ':');
    } else {
      return name.replaceAll('-', '.');
    }
  }

  bool get isDartLibrary => name.startsWith("dart-");

  Item memberNamed(String name, {Function orElse : nothing}) {
    if (name == null) return orElse();
    if (!isLoaded) return orElse();
    for (var category in
        [classes, functions, variables, operators, typedefs, errors]) {
      var member = category.memberNamed(name, orElse: nothing);
      if (member != null) return member;
    }
    return orElse();
  }
}

/**
 * An [Item] that describes a single Dart class.
 */
@reflectable class Class extends LazyItem {

  Category functions;
  Category variables;
  Category constructs;
  get constructors => constructs;
  Category operators;
  LinkableType superClass;
  bool isAbstract;
  String previewComment;
  AnnotationGroup annotations;
  List<LinkableType> implements = [];
  List<LinkableType> subclasses = [];
  List<String> generics = [];

  Category _instanceVariables;
  Category _staticVariables;
  Category _instanceFunctions;
  Category _staticFunctions;
  void flushCaches() {
    _instanceVariables = null;
    _staticVariables = null;
    _instanceFunctions = null;
    _staticFunctions = null;
  }

  Category get instanceVariables {
    if (_instanceVariables == null) {
      _instanceVariables = new Category.forInstanceMembers(variables.content,
          "Properties");
    }
    return _instanceVariables;
  }
  Category get staticVariables {
    if (_staticVariables == null) {
      _staticVariables = new Category.forStaticMembers(variables.content,
          "Static properties");
    }
    return _staticVariables;
  }
  Category get instanceFunctions {
    if (_instanceFunctions == null) {
      _instanceFunctions = new Category.forInstanceMembers(functions.content,
          "Methods");
    }
    return _instanceFunctions;
  }
  Category get staticFunctions {
    if (_staticFunctions == null) {
      _staticFunctions = new Category.forStaticMembers(functions.content,
          "Static methods");
    }
    return _staticFunctions;
  }

  /// Creates a [Class] placeholder object with null fields.
  Class.forPlaceholder(String location, String previewComment)
      : super(location, new DocsLocation(location).memberName, previewComment) {
    operators = new Category.forFunctions(null, 'placeholder');
    variables = new Category.forVariables(null, null, null);
    constructs = new Category.forFunctions(null, 'placeholder');
    functions = new Category.forFunctions(null, 'placeholder');
  }

  /// Normal constructor for testing.
  Class(Map yaml) : super(yaml['qualifiedName'], yaml['name'], '') {
    loadValues(yaml);
  }

  /// The link to an anchor within a larger page, if appropriate. For classes
  /// we link directly to their page instead.
  DocsLocation get anchorHrefLocation => location;

  void addToHierarchy() {
    super.addToHierarchy();
    if (isLoaded) {
      [functions, constructs, operators].forEach((category) {
        category.content.forEach((clazz) {
          buildHierarchy(clazz, this);
        });
      });
    }
  }

  void loadValues(Map yaml) {
    flushCaches();
    comment = _wrapComment(yaml['comment']);
    isAbstract = yaml['isAbstract'] == 'true';
    superClass = new LinkableType(yaml['superclass']);
    subclasses = yaml['subclass'] == null ? [] :
      yaml['subclass'].map((item) => new LinkableType(item)).toList();
    annotations = new AnnotationGroup(yaml['annotations']);
    implements = yaml['implements'] == null ? [] :
        yaml['implements'].map((item) => new LinkableType(item)).toList();
    var genericValues = yaml['generics'];
    if (genericValues != null) {
      genericValues.keys.forEach((generic) => generics.add(generic));
    }
    var setters, getters, methods, operates, constructors;
    var allMethods = yaml['methods'];
    if (allMethods != null) {
      setters = allMethods['setters'];
      getters = allMethods['getters'];
      methods = allMethods['methods'];
      operates = allMethods['operators'];
      constructors = allMethods['constructors'];
    }
    variables = new Category.forVariables(yaml['variables'], getters, setters);
    functions = new Category.forFunctions(methods, 'Methods', className: name,
        owner: this);
    operators = new Category.forFunctions(operates, 'Operators',
        isOperator: true, className: name, owner: this);
    constructs = new Category.forFunctions(constructors, 'Constructors',
        isConstructor: true, className: name, owner: this);
    var inheritedMethods = yaml['inheritedMethods'];
    var inheritedVariables = yaml['inheritedVariables'];
    if (inheritedMethods != null) {
      setters = inheritedMethods['setters'];
      getters = inheritedMethods['getters'];
      methods = inheritedMethods['methods'];
      operates = inheritedMethods['operators'];
    }
    _addVariable(inheritedVariables);
    _addVariable(setters, isSetter: true);
    _addVariable(getters, isGetter: true);
    _addMethod(methods);
    _addMethod(operates, isOperator: true);
    _sort([this.functions.content, this.variables.content,
           this.constructs.content, this.operators.content]);
    isLoaded = true;
  }

  /// Adds an inherited variable to [variables] if not present.
  void _addVariable(Map items, {isSetter: false, isGetter: false}) {
    if (items != null) {
      items.values.forEach((item) {
        var object = new Variable(item, isSetter: isSetter,
            isGetter: isGetter, inheritedFrom: item['qualifiedName'],
            commentFrom: item['commentFrom'], owner: this);
        variables.addInheritedItem(this, object);
      });
    }
  }

  /// Adds an inherited method to the correct [Category] if not present.
  void _addMethod(Map items, {isOperator: false}) {
    if (items != null) {
      items.values.forEach((item) {
        var object = new Method(item, isOperator: isOperator,
            inheritedFrom: item['qualifiedName'],
            commentFrom: item['commentFrom'], className: name, owner: this);
        var location = isOperator ? this.operators : this.functions;
        location.addInheritedItem(this, object);
      });
    }
  }

  String get nameWithGeneric {
    var out = new StringBuffer();
    out.write(name);
    if (generics.isNotEmpty) {
      out.write("<");
      // Use a non-breaking space character, not &nbsp; because this will
      // get escaped.
      out.write(generics.join(",\u{00A0}"));
      out.write(">");
    }
    return out.toString();
  }

  Item memberNamed(String name, {Function orElse : nothing}) {
    if (name == null) return orElse();
    for (var category in
        [annotations, constructs, functions, operators, variables]) {
      var member =  category == null ? null :
          category.memberNamed(name, orElse: nothing);
      if (member != null) return member;
    }
    return orElse();
  }

}

/**
 * A collection of [Annotation]s.
 */
@reflectable class AnnotationGroup {

  List<String> supportedBrowsers = [];
  List<Annotation> annotations = [];
  String domName;

  Item memberNamed(String name, {Function orElse : nothing}) {
    for (var annotation in annotations) {
      if (annotation.name == name) return annotation;
    }
    return orElse();
  }

  AnnotationGroup(List annotes) {
    if (annotes != null) {
      annotes.forEach((annotation) {
        if (annotation['name'] == 'metadata.SupportedBrowser') {
          supportedBrowsers.add(annotation['parameters'].toList().join(' '));
        } else if (annotation['name'] == 'metadata.DomName') {
          domName = annotation['parameters'].first;
        } else {
          annotations.add(new Annotation(annotation));
        }
      });
    }
  }
}

/**
 * A single annotation to an [Item].
 */
@reflectable class Annotation {

  String qualifiedName;
  LinkableType link;
  List<String> parameters;

  Annotation(Map yaml) {
    qualifiedName = yaml['name'];
    link = new LinkableType(qualifiedName);
    parameters = yaml['parameters'] == null ? [] : yaml['parameters'];
  }
}

/**
 * An [Item] that describes a Dart member with parameters.
 */
@reflectable class Parameterized extends Item {

  List<Parameter> parameters;

  Parameterized(String name, String qualifiedName, [String comment])
      : super(name, qualifiedName, comment);

  /// Creates [Parameter] objects for each parameter to this method.
  List<Parameter> getParameters(Map parameters) {
    var values = [];
    if (parameters != null) {
      parameters.forEach((name, data) {
        values.add(new Parameter(name, data, this));
      });
    }
    return values;
  }
}

/**
 * An [Item] that describes a single Dart typedef.
 */
@reflectable class Typedef extends Parameterized {

  LinkableType type;
  AnnotationGroup annotations;

  Typedef(Map yaml) : super(yaml['name'], yaml['qualifiedName'],
      _wrapComment(yaml['comment'])) {
    type = new LinkableType(yaml['return']);
    parameters = getParameters(yaml['parameters']);
    annotations = new AnnotationGroup(yaml['annotations']);
  }
}

/**
 * An [Item] that describes a single Dart method.
 */
@reflectable class Method extends Parameterized {

  bool isStatic;
  bool isAbstract;
  bool isConstant;
  bool isConstructor;
  String inheritedFrom;
  String commentFrom;
  String className;
  Class owner;
  bool isOperator;
  AnnotationGroup annotations;
  NestedType type;

  Method(Map yaml, {this.isConstructor: false, this.className: '',
      this.isOperator: false, this.inheritedFrom: '',
      String commentFrom: '', this.owner})
        : super(yaml['name'], yaml['qualifiedName'],
            _wrapComment(yaml['comment'])) {
    this.isStatic = yaml['static'] == 'true';
    this.isAbstract = yaml['abstract'] == 'true';
    this.isConstant = yaml['constant'] == 'true';
    this.commentFrom = commentFrom == '' ? yaml['commentFrom'] : commentFrom;
    this.type = new NestedType(yaml['return'].first);
    parameters = getParameters(yaml['parameters']);
    annotations = new AnnotationGroup(yaml['annotations']);
  }

  void addToHierarchy() {
    // TODO(alanknight): Conditionally calling super is very unpleasant.
    if (inheritedFrom != '') super.addToHierarchy();
  }

  void addInheritedComment(item) {
    if (comment == '<span></span>') {
      comment = item.comment;
      commentFrom = item.commentFrom;
    }
  }

  bool get isInherited => inheritedFrom != '' && inheritedFrom != null;

  String get decoratedName => isConstructor ?
      (name != '' ? '$className.$name' : className) : name;

  get linkHref => anchorHref;

  /// The link to an anchor within a larger page, if appropriate.
  /// Note that for an inherited method, the qualified name refers to where
  /// it is actually defined. This returns a link into the local page, which
  /// is based on the owner.
  DocsLocation get anchorHrefLocation {
    var baseLocation = localLocation;
    if (isConstructor && name == '') {
      var locationForUnnamed = baseLocation;
      locationForUnnamed.anchor =
          locationForUnnamed.toHash(locationForUnnamed.memberName);
      return locationForUnnamed;
    } else {
      return anchorHrefLocationFrom(baseLocation);
    }
  }

  /// A location based on the actual page we're in, rather than our inherited
  /// location.
  DocsLocation get localLocation {
    if (!isInherited || owner == null) return location;
    var local = owner.location;
    local.subMemberName = name;
    return local;
  }

  String toString() => decoratedName;
}

/**
 * A single parameter to a [Method].
 */
@reflectable class Parameter {

  String name;
  bool isOptional;
  bool isNamed;
  bool hasDefault;
  NestedType type;
  String defaultValue;
  AnnotationGroup annotations;
  Item owner;

  Parameter(this.name, Map yaml, [this.owner]) {
    this.isOptional = yaml['optional'] == 'true';
    this.isNamed = yaml['named'] == 'true';
    this.hasDefault = yaml['default'] == 'true';
    this.type = new NestedType(yaml['type'].first);
    this.defaultValue = yaml['value'];
    annotations = new AnnotationGroup(yaml['annotations']);
  }

  String get decoratedName => '$name$decoration';

  String get decoration {
    if (hasDefault) {
      if (isNamed) {
        return ': $defaultValue';
      } else {
        return '=$defaultValue';
      }
    }
    return '';
  }

  // For a method parameter we use the special anchor @method.parameter
  // because the parameter name may not be unique on the page
  DocsLocation get anchorHrefLocation {
    if (owner == null) return null;
    var parameterLoc = owner.location.parentLocation;
    parameterLoc.anchor = parameterLoc.toHash("${owner.decoratedName}_$name");
    return parameterLoc;
  }

  String get anchorHref => anchorHrefLocation.withAnchor;

  toString() => "Parameter named $name in $owner";
}

/**
 * A [Container] that describes a single Dart variable.
 */
@reflectable class Variable extends Item {

  bool isFinal;
  bool isStatic;
  bool isAbstract;
  bool isConstant;
  bool isGetter;
  bool isSetter;
  String inheritedFrom;
  String commentFrom;
  Parameter setterParameter;
  NestedType type;
  AnnotationGroup annotations;
  Class owner;

  Variable(Map yaml, {bool isGetter: false, bool isSetter: false,
      String inheritedFrom: '', String commentFrom: '', this.owner})
      : super(yaml['name'], yaml['qualifiedName'],
          _wrapComment(yaml['comment'])) {
    this.isGetter = isGetter;
    this.isSetter = isSetter;
    this.inheritedFrom = inheritedFrom;
    this.commentFrom = commentFrom == '' ? yaml['commentFrom'] : commentFrom;
    isFinal = yaml['final'] == 'true';
    isStatic = yaml['static'] == 'true';
    isConstant = yaml['constant'] == 'true';
    isAbstract = yaml['abstract'] == 'true';
    if (isGetter) {
      type = new NestedType(yaml['return'].first);
    } else if (isSetter) {
      type = new NestedType(yaml['return'].first);
      var parameters = yaml['parameters'];
      var parameterName = parameters.keys.first;
      setterParameter = new Parameter(parameterName,
          parameters[parameterName]);
    } else {
      type = new NestedType(yaml['type'].first);
    }
    annotations = new AnnotationGroup(yaml['annotations']);
  }

  void addInheritedComment(Item item) {
    if (comment == '<span></span>') {
      comment = item.comment;
      if (item is Variable) commentFrom = item.commentFrom;
    }
  }

  bool get isInherited => inheritedFrom != '' && inheritedFrom != null;

  void addToHierarchy() {
    if (inheritedFrom != '') super.addToHierarchy();
  }

  /// The link to an anchor within a larger page, if appropriate.
  /// Note that for an inherited variable, the qualified name refers to where
  /// it is actually defined. This returns a link into the local page, which
  /// is based on the owner.
  DocsLocation get anchorHrefLocation => anchorHrefLocationFrom(localLocation);

  /// A location based on the actual page we're in, rather than our inherited
  /// location.
  DocsLocation get localLocation {
    if (!isInherited || owner == null) return location;
    var local = owner.location;
    local.subMemberName = name;
    return local;
  }
}

/**
 * A Dart type that potentially contains generic parameters.
 */
@reflectable class NestedType {
  LinkableType outer;
  List<NestedType> inner = [];

  NestedType(Map yaml) {
    if (yaml == null) {
      outer = new LinkableType('void');
    } else {
      outer = new LinkableType(yaml['outer']);
      var innerMap = yaml['inner'];
      if (innerMap != null)
      innerMap.forEach((element) => inner.add(new NestedType(element)));
    }
  }

  get isDynamic => outer.isDynamic;
}

/**
 * A Dart type that should link to other [Item]s.
 */
@reflectable class LinkableType {

  /// The resolved qualified name of the type this [LinkableType] represents.
  DocsLocation loc;

  /// The constructor resolves the library name by finding the correct library
  /// from [libraryNames] and changing [type] to match.
  LinkableType(String type) {
    loc = new DocsLocation(type);
  }

  /// The simple name for this type.
  String get simpleType => loc.locationWithoutAnchor.name;

  /// The [Item] describing this type if it has been loaded, otherwise null.
  String get location => loc.withoutAnchor;

  String get qualifiedName => location;

  get isDynamic => simpleType == 'dynamic';
}
