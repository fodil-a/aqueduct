import 'package:aqueduct/src/db/managed/key_path.dart';
import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';
import 'package:aqueduct/src/db/postgresql/mappers/table.dart';
import 'package:aqueduct/src/db/query/matcher_internal.dart';
import 'package:postgres/postgres.dart';

export 'package:aqueduct/src/db/postgresql/mappers/expression.dart';
export 'package:aqueduct/src/db/postgresql/mappers/row.dart';

enum PersistentJoinType { leftOuter }

/// Common interface for values that can be mapped to/from a database.
abstract class PostgresMapper {}

class ColumnMapper extends PostgresMapper {
  ColumnMapper(this.table, this.property, {this.keyPath});

  static List<ColumnMapper> fromKeys(EntityTableMapper table, ManagedEntity entity, List<dynamic> keys) {
    // Ensure the primary key is always available and at 0th index.
    var primaryKeyIndex = keys.indexOf(entity.primaryKey);
    if (primaryKeyIndex == -1) {
      keys.insert(0, entity.primaryKey);
    } else if (primaryKeyIndex > 0) {
      keys.removeAt(primaryKeyIndex);
      keys.insert(0, entity.primaryKey);
    }

    return keys.map((key) {
      if (key is KeyPath) {
        return new ColumnMapper(table, propertyForName(entity, key.propertyKey), keyPath: key.elements);
      }
      return new ColumnMapper(table, propertyForName(entity, key));
    }).toList();
  }

  static ManagedPropertyDescription propertyForName(ManagedEntity entity, String propertyName) {
    var property = entity.properties[propertyName];

    if (property == null) {
      throw new ArgumentError(
          "Could not construct query. Column '$propertyName' does not exist for table '${entity.tableName}'.");
    }

    if (property is ManagedRelationshipDescription && property.relationshipType != ManagedRelationshipType.belongsTo) {
      throw new ArgumentError(
          "Could not construct query. Column '$propertyName' does not exist for table '${entity.tableName}'. "
              "'$propertyName' recognized as ORM relationship, use 'Query.join' instead.");
    }

    return property;
  }

  static Map<ManagedPropertyType, PostgreSQLDataType> typeMap = {
    ManagedPropertyType.integer: PostgreSQLDataType.integer,
    ManagedPropertyType.bigInteger: PostgreSQLDataType.bigInteger,
    ManagedPropertyType.string: PostgreSQLDataType.text,
    ManagedPropertyType.datetime: PostgreSQLDataType.timestampWithoutTimezone,
    ManagedPropertyType.boolean: PostgreSQLDataType.boolean,
    ManagedPropertyType.doublePrecision: PostgreSQLDataType.double,
    ManagedPropertyType.document: PostgreSQLDataType.json
  };

  static Map<MatcherOperator, String> symbolTable = {
    MatcherOperator.lessThan: "<",
    MatcherOperator.greaterThan: ">",
    MatcherOperator.notEqual: "!=",
    MatcherOperator.lessThanEqualTo: "<=",
    MatcherOperator.greaterThanEqualTo: ">=",
    MatcherOperator.equalTo: "="
  };

  final EntityTableMapper table;
  final ManagedPropertyDescription property;
  final List<String> keyPath;

  bool fetchAsForeignKey = false;

  String get typeSuffix {
    var type = PostgreSQLFormat.dataTypeStringForDataType(typeMap[property.type.kind]);
    if (type != null) {
      return ":$type";
    }

    return "";
  }

  dynamic convertValueForStorage(dynamic value) {
    if (property is ManagedAttributeDescription) {
      ManagedAttributeDescription p = property;
      if (p.isEnumeratedValue) {
        return property.convertToPrimitiveValue(value);
      } else if (p.type.kind == ManagedPropertyType.document) {
        if (value is Document) {
          return value.data;
        } else if (value is Map || value is List) {
          return value;
        }

        throw new ArgumentError("Invalid data type for 'Document'. Must be 'Document', 'Map', or 'List'.");
      }
    }

    return value;
  }

  dynamic convertValueFromStorage(dynamic value) {
    if (value == null) {
      return null;
    }

    if (property is ManagedAttributeDescription) {
      ManagedAttributeDescription p = property;
      if (p.isEnumeratedValue) {
        return property.convertFromPrimitiveValue(value);
      } else if (p.type.kind == ManagedPropertyType.document) {
        return new Document(value);
      }
    }

    return value;
  }

  String columnName({bool withTypeSuffix: false, bool withTableNamespace: false, String withPrefix}) {
    var name = property.name;

    if (property is ManagedRelationshipDescription) {
      var relatedPrimaryKey = (property as ManagedRelationshipDescription).destinationEntity.primaryKey;
      name = "${name}_$relatedPrimaryKey";
    } else if (keyPath != null) {
      final keys = keyPath.map((k) => k is String ? "'$k'" : k).join("->");
      name = "$name->$keys";
    }

    if (withTypeSuffix) {
      name = "$name$typeSuffix";
    }

    if (withTableNamespace) {
      return "${table.tableReference}.$name";
    } else if (withPrefix != null) {
      return "$withPrefix$name";
    }

    return name;
  }
}

class PropertyValueMapper extends ColumnMapper {
  PropertyValueMapper(EntityTableMapper table, ManagedPropertyDescription property, dynamic value)
      : super(table, property) {
    this.value = convertValueForStorage(value);
  }

  dynamic value;
}