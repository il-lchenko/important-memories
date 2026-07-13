// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'events_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$eventsHash() => r'36fe206143d893f67ee00fef9dc7032dc88485a2';

/// See also [events].
@ProviderFor(events)
final eventsProvider = FutureProvider<List<Map<String, dynamic>>>.internal(
  events,
  name: r'eventsProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$eventsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef EventsRef = FutureProviderRef<List<Map<String, dynamic>>>;
String _$createEventHash() => r'dd33b145d5d48cd7ca2f61f857be466ce9b186a9';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// See also [createEvent].
@ProviderFor(createEvent)
const createEventProvider = CreateEventFamily();

/// See also [createEvent].
class CreateEventFamily extends Family<AsyncValue<Map<String, dynamic>>> {
  /// See also [createEvent].
  const CreateEventFamily();

  /// See also [createEvent].
  CreateEventProvider call(
    Map<String, dynamic> data,
  ) {
    return CreateEventProvider(
      data,
    );
  }

  @override
  CreateEventProvider getProviderOverride(
    covariant CreateEventProvider provider,
  ) {
    return call(
      provider.data,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'createEventProvider';
}

/// See also [createEvent].
class CreateEventProvider
    extends AutoDisposeFutureProvider<Map<String, dynamic>> {
  /// See also [createEvent].
  CreateEventProvider(
    Map<String, dynamic> data,
  ) : this._internal(
          (ref) => createEvent(
            ref as CreateEventRef,
            data,
          ),
          from: createEventProvider,
          name: r'createEventProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$createEventHash,
          dependencies: CreateEventFamily._dependencies,
          allTransitiveDependencies:
              CreateEventFamily._allTransitiveDependencies,
          data: data,
        );

  CreateEventProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.data,
  }) : super.internal();

  final Map<String, dynamic> data;

  @override
  Override overrideWith(
    FutureOr<Map<String, dynamic>> Function(CreateEventRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: CreateEventProvider._internal(
        (ref) => create(ref as CreateEventRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        data: data,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<Map<String, dynamic>> createElement() {
    return _CreateEventProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is CreateEventProvider && other.data == data;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, data.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin CreateEventRef on AutoDisposeFutureProviderRef<Map<String, dynamic>> {
  /// The parameter `data` of this provider.
  Map<String, dynamic> get data;
}

class _CreateEventProviderElement
    extends AutoDisposeFutureProviderElement<Map<String, dynamic>>
    with CreateEventRef {
  _CreateEventProviderElement(super.provider);

  @override
  Map<String, dynamic> get data => (origin as CreateEventProvider).data;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
