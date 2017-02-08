import 'dart:async';

import '../db.dart';
import '../query/mixin.dart';
import 'property_mapper.dart';
import 'query_builder.dart';

class PostgresQuery<InstanceType extends ManagedObject> extends Object
    with QueryMixin<InstanceType>
    implements Query<InstanceType> {
  PostgresQuery(this.context);

  ManagedContext context;

  @override
  Future<InstanceType> insert() async {
    var builder = new PostgresQueryBuilder(entity,
        returningProperties: propertiesToFetch,
        values: valueMap ?? values?.backingMap);

    var buffer = new StringBuffer();
    buffer.write("INSERT INTO ${builder.primaryTableDefinition} ");
    buffer.write("(${builder.valuesColumnString}) ");
    buffer.write("VALUES (${builder.insertionValueString}) ");

    if ((builder.returningOrderedMappers?.length ?? 0) > 0) {
      buffer.write("RETURNING ${builder.returningColumnString}");
    }

    var results = await context.persistentStore.executeQuery(
        buffer.toString(), builder.substitutionValueMap, timeoutInSeconds);

    return builder.instancesForRows(results).first;
  }

  @override
  Future<List<InstanceType>> update() async {
    var builder = new PostgresQueryBuilder(entity,
        returningProperties: propertiesToFetch,
        values: valueMap ?? values?.backingMap,
        whereBuilder: (hasWhereBuilder ? where : null),
        predicate: predicate);

    var buffer = new StringBuffer();
    buffer.write("UPDATE ${builder.primaryTableDefinition} ");
    buffer.write("SET ${builder.updateValueString} ");

    if (builder.whereClause != null) {
      buffer.write("WHERE ${builder.whereClause} ");
    } else if (!canModifyAllInstances) {
      throw canModifyAllInstancesError;
    }

    if ((builder.returningOrderedMappers?.length ?? 0) > 0) {
      buffer.write("RETURNING ${builder.returningColumnString}");
    }

    var results = await context.persistentStore.executeQuery(
        buffer.toString(), builder.substitutionValueMap, timeoutInSeconds);

    return builder.instancesForRows(results);
  }

  @override
  Future<InstanceType> updateOne() async {
    var results = await update();
    if (results.length == 1) {
      return results.first;
    } else if (results.length == 0) {
      return null;
    }

    throw new QueryException(QueryExceptionEvent.internalFailure,
        message:
            "updateOne modified more than one row, this is a serious error.");
  }

  @override
  Future<int> delete() async {
    var builder = new PostgresQueryBuilder(entity,
        predicate: predicate, whereBuilder: hasWhereBuilder ? where : null);

    var buffer = new StringBuffer();
    buffer.write("DELETE FROM ${builder.primaryTableDefinition} ");

    if (builder.whereClause != null) {
      buffer.write("WHERE ${builder.whereClause} ");
    } else if (!canModifyAllInstances) {
      throw canModifyAllInstancesError;
    }

    return context.persistentStore.executeQuery(
        buffer.toString(), builder.substitutionValueMap, timeoutInSeconds,
        returnType: PersistentStoreQueryReturnType.rowCount);
  }

  @override
  Future<InstanceType> fetchOne() async {
    var rowMapper = createFetchMapper();

    if (!rowMapper.containsJoins) {
      fetchLimit = 1;
    }

    var results = await _fetch(rowMapper);
    if (results.length == 1) {
      return results.first;
    } else if (results.length > 1) {
      throw new QueryException(QueryExceptionEvent.requestFailure,
          message:
              "Query expected to fetch one instance, but ${results.length} instances were returned.");
    }

    return null;
  }

  @override
  Future<List<InstanceType>> fetch() async {
    return _fetch(createFetchMapper());
  }

  //////

  PostgresQueryBuilder createFetchMapper() {
    var allSortDescriptors =
        new List<QuerySortDescriptor>.from(sortDescriptors ?? []);
    if (pageDescriptor != null) {
      validatePageDescriptor();
      var pageSortDescriptor = new QuerySortDescriptor(
          pageDescriptor.propertyName, pageDescriptor.order);
      allSortDescriptors.insert(0, pageSortDescriptor);

      if (pageDescriptor.boundingValue != null) {
        if (pageDescriptor.order == QuerySortOrder.ascending) {
          where[pageDescriptor.propertyName] =
              whereGreaterThan(pageDescriptor.boundingValue);
        } else {
          where[pageDescriptor.propertyName] =
              whereLessThan(pageDescriptor.boundingValue);
        }
      }
    }

    var builder = new PostgresQueryBuilder(entity,
        returningProperties: propertiesToFetch,
        predicate: predicate,
        whereBuilder: hasWhereBuilder ? where : null,
        nestedRowMappers: rowMappersFromSubqueries,
        sortDescriptors: allSortDescriptors);

    if (builder.containsJoins && pageDescriptor != null) {
      throw new QueryException(QueryExceptionEvent.requestFailure,
          message:
              "Cannot use 'Query<T>' with both 'pageDescriptor' and joins currently.");
    }

    return builder;
  }

  Future<List<InstanceType>> _fetch(PostgresQueryBuilder builder) async {
    var buffer = new StringBuffer();
    buffer.write("SELECT ${builder.returningColumnString} ");
    buffer.write("FROM ${builder.primaryTableDefinition} ");

    if (builder.containsJoins) {
      buffer.write("${builder.joinString} ");
    }

    if (builder.whereClause != null) {
      buffer.write("WHERE ${builder.whereClause} ");
    }

    buffer.write("${builder.orderByString} ");

    if (fetchLimit != 0) {
      buffer.write("LIMIT ${fetchLimit} ");
    }

    if (offset != 0) {
      buffer.write("OFFSET ${offset} ");
    }

    var results = await context.persistentStore.executeQuery(
        buffer.toString(), builder.substitutionValueMap, timeoutInSeconds);

    return builder.instancesForRows(results);
  }

  void validatePageDescriptor() {
    var prop = entity.attributes[pageDescriptor.propertyName];
    if (prop == null) {
      throw new QueryException(QueryExceptionEvent.requestFailure,
          message:
              "Property '${pageDescriptor.propertyName}' in pageDescriptor does not exist on '${entity.tableName}'.");
    }

    if (pageDescriptor.boundingValue != null &&
        !prop.isAssignableWith(pageDescriptor.boundingValue)) {
      throw new QueryException(QueryExceptionEvent.requestFailure,
          message:
              "Property '${pageDescriptor.propertyName}' in pageDescriptor has invalid type (Expected: '${prop.type}' Got: ${pageDescriptor.boundingValue.runtimeType}').");
    }
  }

  List<RowMapper> get rowMappersFromSubqueries {
    return subQueries?.keys?.map((relationshipDesc) {
          var subQuery = subQueries[relationshipDesc] as PostgresQuery;
          var joinElement = new RowMapper(PersistentJoinType.leftOuter,
              relationshipDesc, subQuery.propertiesToFetch,
              predicate: subQuery.predicate,
              whereBuilder: subQuery.hasWhereBuilder ? subQuery.where : null);
          joinElement.addRowMappers(subQuery.rowMappersFromSubqueries);

          return joinElement;
        })?.toList() ??
        [];
  }

  static QueryException canModifyAllInstancesError =
      new QueryException(QueryExceptionEvent.internalFailure,
          message: "Query would "
              "impact all records. This could be a destructive error. Set "
              "canModifyAllInstances on the Query to execute anyway.");
}
