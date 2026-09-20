import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pedido_crud/Planos/PlanService.dart';

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
  @override
  String? get email => 'buyer@example.com';
}

class _Auth extends Fake implements FirebaseAuth {
  User? user = _User('buyer');
  final changes = StreamController<User?>.broadcast();
  @override
  User? get currentUser => user;
  @override
  Stream<User?> authStateChanges() => changes.stream;
}

class _Firestore extends Fake implements FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{
    'users/buyer': {'companyId': 'company', 'planId': 'free', 'plan': 'free'},
    'subscriptions/company': {'userId': 'buyer', 'planId': 'free', 'status': 'active'},
    'plans/free': {
      'id': 'free',
      'limits': {'maxClients': 2},
    },
    'plans/starter': {
      'id': 'starter',
      'limits': {'maxClients': 10},
    },
    'plans/premium': {
      'id': 'premium',
      'limits': {'maxClients': -1},
    },
  };
  final orders = <Map<String, dynamic>>[];
  final reads = <String>[];
  final sources = <Source?>[];
  Future<void> Function(String)? beforeRead;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
  Future<DocumentSnapshot<Map<String, dynamic>>> read(
    String path,
    GetOptions? options,
  ) async {
    reads.add(path);
    sources.add(options?.source);
    final value = documents[path];
    final data = value == null ? null : Map<String, dynamic>.from(value);
    await beforeRead?.call(path);
    return _Snapshot(data);
  }
}

// In-memory query doubles exercise author and monthly filtering.
// ignore: subtype_of_sealed_class
class _Query extends Fake implements Query<Map<String, dynamic>> {
  _Query(this.rows);
  final List<Map<String, dynamic>> rows;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #where) {
      final field = invocation.positionalArguments.first as String;
      final args = invocation.namedArguments;
      return _Query(rows.where((row) {
        if (args[#isEqualTo] != null) return row[field] == args[#isEqualTo];
        final value = row[field] as Timestamp;
        if (args[#isGreaterThanOrEqualTo] != null) {
          return value.compareTo(args[#isGreaterThanOrEqualTo] as Timestamp) >= 0;
        }
        return value.compareTo(args[#isLessThan] as Timestamp) < 0;
      }).toList());
    }
    if (invocation.memberName == #limit) return _Query(rows.take(invocation.positionalArguments.first as int).toList());
    if (invocation.memberName == #get) {
      return Future<QuerySnapshot<Map<String, dynamic>>>.value(_QuerySnapshot(rows));
    }
    return super.noSuchMethod(invocation);
  }
}
// ignore: subtype_of_sealed_class
class _QuerySnapshot extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  _QuerySnapshot(this.rows);
  final List<Map<String, dynamic>> rows;
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => rows.map(_QueryDocument.new).toList();
}
// ignore: subtype_of_sealed_class
class _QueryDocument extends Fake implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _QueryDocument(this.row);
  final Map<String, dynamic> row;
  @override
  Map<String, dynamic> data() => row;
}

// In-memory test double; never used with the Firestore platform.
// ignore: subtype_of_sealed_class
class _Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.firestore, this.path);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      _Query(path == 'users' ? firestore.documents.entries.where((e) => e.key.startsWith('users/')).map((e) => e.value).toList() : firestore.orders).noSuchMethod(invocation);
  @override
  final _Firestore firestore;
  @override
  final String path;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document(firestore, '${this.path}/$path');
}

// In-memory test double; never used with the Firestore platform.
// ignore: subtype_of_sealed_class
class _Document extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  _Document(this.firestore, this.path);
  @override
  final _Firestore firestore;
  @override
  final String path;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      firestore.read(path, options);
}

// In-memory test double; never used with the Firestore platform.
// ignore: subtype_of_sealed_class
class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.value);
  final Map<String, dynamic>? value;
  @override
  bool get exists => value != null;
  @override
  Map<String, dynamic>? data() => value;
}

void main() {
  late _Auth auth;
  late _Firestore firestore;
  late PlanService service;
  setUp(() {
    auth = _Auth();
    firestore = _Firestore();
    service = PlanService.forTesting(auth: auth, firestore: firestore);
  });
  tearDown(() async {
    service.dispose();
    await auth.changes.close();
  });

  test('count loads legacy user by email without inheriting admin plan', () async {
    final record = firestore.documents.remove('users/buyer')!;
    firestore.documents['users/legacy'] = {...record, 'emailKey': 'buyer@example.com'};
    firestore.documents['subscriptions/company'] = {
      'userId': 'admin', 'planId': 'premium', 'status': 'active',
    };
    expect(await service.getCurrentOrdersMonthCount(), 0);
    expect(service.isLoaded, isTrue);
    expect(service.companyId, 'company');
    expect(service.planId, 'free');
  });

  test('missing user fails validation instead of returning zero orders', () async {
    firestore.documents.remove('users/buyer');
    await expectLater(service.getCurrentOrdersMonthCount(), throwsStateError);
    expect(service.isLoaded, isFalse);
  });

  test('monthly orders belong to original author with legacy fallback', () async {
    final now = DateTime.now();
    Map<String, dynamic> order(String user, {String? creator, DateTime? date}) => {
      'companyId': 'company', 'userId': user, 'createdByUid': creator,
      'data': Timestamp.fromDate(date ?? now),
    };
    firestore.orders.addAll([
      order('buyer', creator: 'buyer'),
      order('buyer'),
      order('buyer', creator: 'administrator'),
      order('administrator', creator: 'buyer'),
      order('buyer', date: DateTime(now.year, now.month - 1, 1)),
      order('buyer', date: DateTime(now.year, now.month + 1, 1)),
    ]);
    await service.reload(forceServer: true);
    expect(await service.getCurrentOrdersMonthCount(), 3);
  });

  test('employee does not inherit administrator Premium', () async {
    firestore.documents['subscriptions/company'] = {
      'userId': 'administrator', 'planId': 'premium', 'status': 'active',
    };
    await service.reload(forceServer: true);
    expect(service.planId, 'free');
  });

  test('personal user fallback preserves own Premium', () async {
    firestore.documents['subscriptions/company']!['userId'] = 'another-user';
    firestore.documents['users/buyer']!['planId'] = 'premium';
    await service.reload(forceServer: true);
    expect(service.planId, 'premium');
  });

  test('subscription is authoritative over legacy user fields', () async {
    firestore.documents['subscriptions/company']!['planId'] = 'premium';
    await service.reload(forceServer: true);
    expect(service.isPremiumActive, isTrue);
    expect(service.getLimit('maxClients'), -1);
    expect(firestore.sources, everyElement(Source.server));
    // Writes are not implemented by the fake: an attempted write fails.
  });

  test('explicit Free subscription overrides stale Premium user', () async {
    firestore.documents['users/buyer']!['planId'] = 'premium';
    firestore.documents['users/buyer']!['plan'] = 'premium';
    await service.load();
    expect(service.planId, 'free');
  });

  test('expired subscription is not replaced by a user fallback', () async {
    firestore.documents['subscriptions/company'] = {
      'planId': 'premium',
      'status': 'expired',
      'userId': 'buyer',
    };
    await service.load();
    expect(service.planStatus, 'expired');
    expect(service.isPremiumActive, isFalse);
  });

  for (final plan in ['free', 'starter', 'premium']) {
    test('missing subscription falls back to planId $plan', () async {
      firestore.documents.remove('subscriptions/company');
      firestore.documents['users/buyer']!['planId'] = plan;
      firestore.documents['users/buyer']!['plan'] = 'starter';
      await service.reload(forceServer: true);
      expect(service.planId, plan);
    });
  }

  test('empty planId keeps legacy plan fallback', () async {
    firestore.documents.remove('subscriptions/company');
    firestore.documents['users/buyer']!['planId'] = ' ';
    firestore.documents['users/buyer']!['plan'] = 'starter';
    await service.reload(forceServer: true);
    expect(service.planId, 'starter');
  });

  test('publishes plan and limits together after catalog finishes', () async {
    await service.load();
    final events = <List<Object>>[];
    service.addListener(() {
      events.add([service.planId, service.getLimit('maxClients')]);
    });
    firestore.documents['subscriptions/company']!['planId'] = 'premium';
    final entered = Completer<void>();
    final release = Completer<void>();
    firestore.beforeRead = (path) async {
      if (path == 'plans/premium') {
        entered.complete();
        await release.future;
      }
    };
    final refresh = service.reload(forceServer: true);
    await entered.future;
    expect(service.planId, 'free');
    expect(service.getLimit('maxClients'), 2);
    expect(events, isEmpty);
    release.complete();
    await refresh;
    expect(events, [
      ['premium', -1],
    ]);
    expect(firestore.reads.length, 6);
  });

  test('failed refresh preserves the complete previous state', () async {
    await service.load();
    firestore.documents['subscriptions/company']!['planId'] = 'premium';
    firestore.beforeRead = (path) async {
      if (path == 'plans/premium') throw StateError('offline');
    };
    var notifications = 0;
    service.addListener(() => notifications++);
    await expectLater(service.reload(forceServer: true), throwsStateError);
    expect(service.planId, 'free');
    expect(service.getLimit('maxClients'), 2);
    expect(service.isLoaded, isTrue);
    expect(notifications, 0);
  });

  test('ordinary concurrent loads share Firestore requests', () async {
    final release = Completer<void>();
    firestore.beforeRead = (path) async {
      if (path == 'users/buyer') await release.future;
    };
    final first = service.load();
    final second = service.load();
    expect(identical(first, second), isTrue);
    release.complete();
    await Future.wait([first, second]);
    expect(firestore.reads.length, 3);
  });

  test('post-purchase refresh wins over an old in-flight load', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    firestore.beforeRead = (path) async {
      if (path == 'plans/free') {
        entered.complete();
        await release.future;
      }
    };
    final oldLoad = service.load();
    await entered.future;
    firestore.documents['subscriptions/company']!['planId'] = 'premium';
    await service.reload(forceServer: true);
    release.complete();
    await oldLoad;
    expect(service.planId, 'premium');
    expect(service.getLimit('maxClients'), -1);
  });

  test('logout discards an in-flight Premium result', () async {
    firestore.documents['subscriptions/company']!['planId'] = 'premium';
    final entered = Completer<void>();
    final release = Completer<void>();
    firestore.beforeRead = (path) async {
      if (path == 'plans/premium') {
        entered.complete();
        await release.future;
      }
    };
    final refresh = service.load();
    await entered.future;
    auth.user = null;
    auth.changes.add(null);
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await refresh;
    expect(service.isLoaded, isFalse);
    expect(service.planId, 'free');
  });

  testWidgets('mounted consumer updates without extra reads', (tester) async {
    await service.load();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ListenableBuilder(
          listenable: service,
          builder: (_, _) => Text(service.isPremium ? 'unlocked' : 'locked'),
        ),
      ),
    );
    expect(find.text('locked'), findsOneWidget);
    firestore.documents['subscriptions/company']!['planId'] = 'premium';
    await service.reload(forceServer: true);
    await tester.pump();
    expect(find.text('unlocked'), findsOneWidget);
    expect(firestore.reads.length, 6);
    await tester.pumpWidget(const SizedBox.shrink());
    await service.reload(forceServer: true);
    expect(tester.takeException(), isNull);
  });
}
