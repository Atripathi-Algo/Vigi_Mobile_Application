import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vigil/data/store.dart';
import 'package:vigil/services/home_widgets.dart';

void main() {
  late VigilStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dotenv.testLoad(fileInput: '');
    store = await VigilStore.load();
  });

  test('the Spend widget shows dots until amounts are allowed in Settings', () {
    expect(HomeWidgets.spendData(store)['spend_amount'], '₹ ••••');
    store.setToggle('widgetSpend', true);
    store.setBudget(2500000);
    final Map<String, String> d = HomeWidgets.spendData(store);
    expect(d['spend_amount'], '₹0');
    expect(d['spend_of'], 'of ₹25,000');
  });

  test('the Garage widget says so when there is no bike, and otherwise shows the first one', () {
    expect(HomeWidgets.garageData(store, DateTime.now())['garage_odo'], 'No bike yet');
    store.addBike(make: 'Royal Enfield', model: 'Meteor 350', tankL: 15, odometer: 9412);
    final Map<String, String> d = HomeWidgets.garageData(store, DateTime.now());
    expect((d['garage_name'], d['garage_odo']), ('Meteor 350', '9,412 km'));
  });
}
