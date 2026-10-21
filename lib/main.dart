import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);
  runApp(const WarungBarokahApp());
}

class WarungBarokahApp extends StatelessWidget {
  const WarungBarokahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Warung Barokah Kiarajangkung',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
      ),
      home: const MainHomeScreen(),
    );
  }
}

class Product {
  String id;
  String name;
  String category;
  double buyPrice;  
  double price;     
  int stock;

  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.buyPrice,
    required this.price,
    required this.stock,
  });
}

class CartItem {
  Product product;
  int quantity;

  CartItem({required this.product, required this.quantity});

  double get totalPrice => product.price * quantity;
  double get totalBuyPrice => product.buyPrice * quantity;
}

class TransactionRecord {
  String id;
  DateTime date;
  List<CartItem> items;
  double subtotal;
  double discount;
  double tax;
  double total;
  double payAmount;
  double change;
  double customNetProfit;
  String itemsSummary;

  TransactionRecord({
    required this.id,
    required this.date,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.payAmount,
    required this.change,
    this.customNetProfit = 0,
    this.itemsSummary = '',
  });

  double get totalCapital => items.fold(0, (sum, item) => sum + item.totalBuyPrice);
  double get netProfit => items.isNotEmpty ? ((subtotal - discount) - totalCapital) : customNetProfit;
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 0;

  List<Product> products = [];
  List<CartItem> cart = [];
  List<TransactionRecord> transactions = [];

  TextEditingController searchKasirController = TextEditingController();
  String searchKasirQuery = '';
  String selectedCategory = 'Semua';

  TextEditingController searchMasterController = TextEditingController();
  String searchMasterQuery = '';
  String productSortOption = 'Default';

  final String googleSheetUrl =
      'https://script.google.com/macros/s/AKfycbx0Vw5ldIELsmoXzTNiW9VBeLYeNxaJ15CaX9IhnjBPIWqdxIVJSYN8lUPjMMjyOiet/exec';

  final currencyFormatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    fetchAllDataFromGoogleSheets();
  }

  void fetchAllDataFromGoogleSheets() {
    fetchProductsFromGoogleSheets();
    fetchTransactionsFromGoogleSheets();
  }

  Future<void> fetchProductsFromGoogleSheets() async {
    try {
      final response = await http.get(Uri.parse(googleSheetUrl));
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          setState(() {
            products = data
                .map((item) => Product(
                      id: item['id'].toString(),
                      name: item['name'] ?? '',
                      category: item['category'] ?? 'Umum',
                      buyPrice: (item['buyPrice'] as num?)?.toDouble() ?? 0,
                      price: (item['price'] as num?)?.toDouble() ?? 0,
                      stock: (item['stock'] as num?)?.toInt() ?? 0,
                    ))
                .toList();
          });
        }
      }
    } catch (e) {
      print("Gagal memuat produk dari Google Sheets: $e");
    }
  }

  // Mengambil daftar riwayat transaksi dari Google Sheets
  Future<void> fetchTransactionsFromGoogleSheets() async {
    try {
      final response = await http.get(Uri.parse('$googleSheetUrl?action=getTransactions'));
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          setState(() {
            transactions = data.map((item) {
              DateTime parsedDate;
              try {
                parsedDate = DateTime.parse(item['date'].toString());
              } catch (_) {
                parsedDate = DateTime.now();
              }

              return TransactionRecord(
                id: item['id'].toString(),
                date: parsedDate,
                items: [],
                subtotal: (item['subtotal'] as num?)?.toDouble() ?? 0,
                discount: (item['discount'] as num?)?.toDouble() ?? 0,
                tax: (item['tax'] as num?)?.toDouble() ?? 0,
                total: (item['total'] as num?)?.toDouble() ?? 0,
                payAmount: (item['total'] as num?)?.toDouble() ?? 0,
                change: 0,
                customNetProfit: (item['netProfit'] as num?)?.toDouble() ?? 0,
                itemsSummary: item['itemsSummary'] ?? '',
              );
            }).toList();
          });
        }
      }
    } catch (e) {
      print("Gagal memuat transaksi dari Google Sheets: $e");
    }
  }

  Future<void> saveProductToGoogleSheets(Product product) async {
    try {
      await http.post(
        Uri.parse(googleSheetUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "action": "saveProduct",
          "id": product.id,
          "name": product.name,
          "category": product.category,
          "buyPrice": product.buyPrice,
          "price": product.price,
          "stock": product.stock,
        }),
      );
    } catch (e) {
      print("Gagal menyimpan produk ke Google Sheets: $e");
    }
  }

  Future<void> saveTransactionToGoogleSheets(TransactionRecord trx) async {
    try {
      String itemsSummary = trx.items
          .map((i) => "${i.product.name} (${i.quantity}x)")
          .join(", ");

      await http.post(
        Uri.parse(googleSheetUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "action": "saveTransaction",
          "id": trx.id,
          "date": DateFormat('yyyy-MM-dd HH:mm:ss').format(trx.date),
          "subtotal": trx.subtotal,
          "discount": trx.discount,
          "tax": trx.tax,
          "total": trx.total,
          "netProfit": trx.netProfit,
          "itemsSummary": itemsSummary,
        }),
      );
    } catch (e) {
      print("Gagal menyimpan transaksi ke Google Sheets: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      buildKasirPage(),
      buildProductManagementPage(),
      buildHistoryPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Warung Barokah',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Kiarajangkung',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed: () {
              fetchAllDataFromGoogleSheets();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Memperbarui data produk & transaksi...')),
              );
            },
          ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: Colors.green[700],
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.shopping_cart), label: 'Kasir'),
          BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2), label: 'Produk/Stok'),
          BottomNavigationBarItem(
              icon: Icon(Icons.history), label: 'Riwayat & Laporan'),
        ],
      ),
    );
  }

  List<String> getCategories() {
    Set<String> categories = {'Semua'};
    for (var p in products) {
      if (p.category.isNotEmpty) {
        categories.add(p.category);
      }
    }
    return categories.toList();
  }

  // ================= 1. HALAMAN KASIR =================
  Widget buildKasirPage() {
    double subtotal = cart.fold(0, (sum, item) => sum + item.totalPrice);
    List<String> categories = getCategories();

    List<Product> filteredProducts = products.where((prod) {
      bool matchesSearch =
          prod.name.toLowerCase().contains(searchKasirQuery.toLowerCase());
      bool matchesCategory =
          selectedCategory == 'Semua' || prod.category == selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: searchKasirController,
            decoration: InputDecoration(
              hintText: 'Cari produk...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchKasirQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          searchKasirController.clear();
                          searchKasirQuery = '';
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
            ),
            onChanged: (value) {
              setState(() {
                searchKasirQuery = value;
              });
            },
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              String cat = categories[index];
              bool isSelected = selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  onSelected: (bool selected) {
                    setState(() {
                      selectedCategory = cat;
                    });
                  },
                  selectedColor: Colors.green[200],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          flex: 2,
          child: filteredProducts.isEmpty
              ? const Center(child: Text('Produk tidak ditemukan'))
              : ListView.builder(
                  itemCount: filteredProducts.length,
                  itemBuilder: (context, index) {
                    final prod = filteredProducts[index];
                    return ListTile(
                      title: Text(prod.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          '${prod.category} | Jual: ${currencyFormatter.format(prod.price)} | Stok: ${prod.stock}'),
                      trailing: ElevatedButton(
                        onPressed: prod.stock > 0
                            ? () {
                                setState(() {
                                  int existingIndex = cart.indexWhere(
                                      (c) => c.product.id == prod.id);
                                  if (existingIndex != -1) {
                                    if (cart[existingIndex].quantity <
                                        prod.stock) {
                                      cart[existingIndex].quantity++;
                                    }
                                  } else {
                                    cart.add(
                                        CartItem(product: prod, quantity: 1));
                                  }
                                });
                              }
                            : null,
                        child: const Text('Tambah'),
                      ),
                    );
                  },
                ),
        ),
        const Divider(thickness: 2),
        Expanded(
          flex: 2,
          child: Container(
            color: Colors.grey[100],
            child: cart.isEmpty
                ? const Center(child: Text('Keranjang Masih Kosong'))
                : ListView.builder(
                    itemCount: cart.length,
                    itemBuilder: (context, index) {
                      final item = cart[index];
                      return ListTile(
                        title: Text(item.product.name),
                        subtitle: Text(
                            '${item.quantity} x ${currencyFormatter.format(item.product.price)} = ${currencyFormatter.format(item.totalPrice)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle,
                                  color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  if (item.quantity > 1) {
                                    item.quantity--;
                                  } else {
                                    cart.removeAt(index);
                                  }
                                });
                              },
                            ),
                            Text('${item.quantity}',
                                style: const TextStyle(fontSize: 16)),
                            IconButton(
                              icon: const Icon(Icons.add_circle,
                                  color: Colors.green),
                              onPressed: () {
                                setState(() {
                                  if (item.quantity < item.product.stock) {
                                    item.quantity++;
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Subtotal Belanja:', style: TextStyle(fontSize: 12)),
                  Text(
                    currencyFormatter.format(subtotal),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                  ),
                ],
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                ),
                onPressed:
                    cart.isEmpty ? null : () => showPaymentDialog(subtotal),
                child: const Text('BAYAR',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        )
      ],
    );
  }

  void showPaymentDialog(double subtotal) {
    TextEditingController discountCtrl = TextEditingController(text: '0');
    TextEditingController taxPercentCtrl = TextEditingController(text: '0');
    TextEditingController payCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double discount = double.tryParse(discountCtrl.text) ?? 0;
            double taxPercent = double.tryParse(taxPercentCtrl.text) ?? 0;
            double taxAmount = (subtotal - discount) * (taxPercent / 100);
            double grandTotal = (subtotal - discount) + taxAmount;

            return AlertDialog(
              title: const Text('Pembayaran & Potongan'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Subtotal:'),
                        Text(currencyFormatter.format(subtotal),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: discountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Diskon / Potongan (Rp)',
                        prefixText: 'Rp ',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (val) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: taxPercentCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'PPN (%)',
                        suffixText: '%',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (val) => setDialogState(() {}),
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('PPN Nominal:'),
                        Text(currencyFormatter.format(taxAmount)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TOTAL BAYAR:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(
                          currencyFormatter.format(grandTotal),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.green[800]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: payCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Uang Diterima',
                        prefixText: 'Rp ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    double bayar = double.tryParse(payCtrl.text) ?? 0;
                    if (bayar >= grandTotal) {
                      double kembalian = bayar - grandTotal;

                      for (var item in cart) {
                        item.product.stock -= item.quantity;
                        saveProductToGoogleSheets(item.product);
                      }

                      TransactionRecord trx = TransactionRecord(
                        id: DateTime.now()
                            .millisecondsSinceEpoch
                            .toString()
                            .substring(7),
                        date: DateTime.now(),
                        items: List.from(cart),
                        subtotal: subtotal,
                        discount: discount,
                        tax: taxAmount,
                        total: grandTotal,
                        payAmount: bayar,
                        change: kembalian,
                      );

                      saveTransactionToGoogleSheets(trx);

                      transactions.add(trx);
                      setState(() {
                        cart.clear();
                      });

                      Navigator.pop(context);
                      showReceiptDialog(trx);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Uang pembayaran tidak cukup!')),
                      );
                    }
                  },
                  child: const Text('Proses & Struk'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> printReceiptViaBluetooth(TransactionRecord trx) async {
    try {
      List<BluetoothInfo> devices = await PrintBluetoothThermal.pairedBluetooths;
      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Tidak ada perangkat Bluetooth tersanding!')),
        );
        return;
      }

      String macAddress = devices.first.macAdress;
      bool status =
          await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);

      if (status) {
        String receiptText = "       WARUNG BAROKAH\n"
            "       KIARAJANGKUNG\n"
            "Sukahening, Tasikmalaya\n"
            "--------------------------------\n"
            "No : #${trx.id}\n"
            "Tgl: ${DateFormat('dd/MM/yyyy HH:mm').format(trx.date)}\n"
            "--------------------------------\n";

        for (var item in trx.items) {
          receiptText += "${item.product.name}\n"
              "  ${item.quantity} x ${currencyFormatter.format(item.product.price)} = ${currencyFormatter.format(item.totalPrice)}\n";
        }

        receiptText += "--------------------------------\n"
            "Subtotal: ${currencyFormatter.format(trx.subtotal)}\n";
        if (trx.discount > 0) {
          receiptText +=
              "Diskon  : -${currencyFormatter.format(trx.discount)}\n";
        }
        if (trx.tax > 0) {
          receiptText += "PPN     : +${currencyFormatter.format(trx.tax)}\n";
        }
        receiptText += "Total   : ${currencyFormatter.format(trx.total)}\n"
            "Bayar   : ${currencyFormatter.format(trx.payAmount)}\n"
            "Kembali : ${currencyFormatter.format(trx.change)}\n"
            "--------------------------------\n"
            " Terimakasih Atas Kunjungan Anda\n\n\n";

        await PrintBluetoothThermal.writeString(
            printText: PrintTextSize(size: 1, text: receiptText));
        await PrintBluetoothThermal.disconnect;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Struk berhasil dicetak!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Gagal terhubung ke printer Bluetooth!')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cetak: $e')),
      );
    }
  }

  void showReceiptDialog(TransactionRecord trx) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('WARUNG BAROKAH KIARAJANGKUNG',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Text('Kiarajangkung, Sukahening, Tasikmalaya',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10)),
                const Divider(),
                Text(
                    'No: #${trx.id} | ${DateFormat('dd/MM/yyyy HH:mm').format(trx.date)}',
                    style: const TextStyle(fontSize: 10)),
                const Divider(),
                if (trx.items.isNotEmpty)
                  ...trx.items.map((item) => Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${item.product.name} x${item.quantity}',
                              style: const TextStyle(fontSize: 12)),
                          Text(currencyFormatter.format(item.totalPrice),
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ))
                else if (trx.itemsSummary.isNotEmpty)
                  Text('Rincian: ${trx.itemsSummary}', style: const TextStyle(fontSize: 11)),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtotal:'),
                    Text(currencyFormatter.format(trx.subtotal)),
                  ],
                ),
                if (trx.discount > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Diskon:'),
                      Text('-${currencyFormatter.format(trx.discount)}',
                          style: const TextStyle(color: Colors.red)),
                    ],
                  ),
                if (trx.tax > 0)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('PPN:'),
                      Text('+${currencyFormatter.format(trx.tax)}'),
                    ],
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(currencyFormatter.format(trx.total),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Bayar:'),
                    Text(currencyFormatter.format(trx.payAmount)),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Kembali:'),
                    Text(currencyFormatter.format(trx.change)),
                  ],
                ),
                const SizedBox(height: 10),
                const Text('Terima Kasih Atas Kunjungan Anda!',
                    style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(context);
                printReceiptViaBluetooth(trx);
              },
              icon: const Icon(Icons.print, size: 18),
              label: const Text('Cetak Bluetooth'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }

  // ================= 2. HALAMAN MANAJEMEN PRODUK =================
  Widget buildProductManagementPage() {
    Map<String, int> salesCount = {};
    for (var trx in transactions) {
      for (var item in trx.items) {
        salesCount[item.product.id] =
            (salesCount[item.product.id] ?? 0) + item.quantity;
      }
    }

    List<Product> filteredMasterProducts = products.where((prod) {
      bool matchesSearch =
          prod.name.toLowerCase().contains(searchMasterQuery.toLowerCase());

      if (productSortOption == 'Stok Kosong') {
        return matchesSearch && prod.stock == 0;
      } else if (productSortOption == 'Stok Menipis (<5)') {
        return matchesSearch && prod.stock > 0 && prod.stock < 5;
      }
      return matchesSearch;
    }).toList();

    filteredMasterProducts.sort((a, b) {
      if (productSortOption == 'Stok Terkecil') {
        return a.stock.compareTo(b.stock);
      } else if (productSortOption == 'Stok Terbesar') {
        return b.stock.compareTo(a.stock);
      } else if (productSortOption == 'Paling Laku') {
        int salesA = salesCount[a.id] ?? 0;
        int salesB = salesCount[b.id] ?? 0;
        return salesB.compareTo(salesA);
      } else {
        return a.name.compareTo(b.name);
      }
    });

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.green[700],
        onPressed: () => showAddProductDialog(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchMasterController,
                    decoration: InputDecoration(
                      hintText: 'Cari stok barang...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searchMasterQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  searchMasterController.clear();
                                  searchMasterQuery = '';
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                    ),
                    onChanged: (value) {
                      setState(() {
                        searchMasterQuery = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButton<String>(
                    value: productSortOption,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'Default', child: Text('Urut: Default')),
                      DropdownMenuItem(value: 'Stok Kosong', child: Text('🔴 Stok Kosong (0)')),
                      DropdownMenuItem(value: 'Stok Menipis (<5)', child: Text('🟡 Stok Menipis (<5)')),
                      DropdownMenuItem(value: 'Stok Terkecil', child: Text('Stok Terkecil')),
                      DropdownMenuItem(value: 'Stok Terbesar', child: Text('Stok Terbesar')),
                      DropdownMenuItem(value: 'Paling Laku', child: Text('Paling Laku')),
                    ],
                    onChanged: (val) {
                      setState(() {
                        productSortOption = val!;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: filteredMasterProducts.isEmpty
                ? const Center(child: Text('Barang tidak ditemukan'))
                : ListView.builder(
                    itemCount: filteredMasterProducts.length,
                    itemBuilder: (context, index) {
                      final prod = filteredMasterProducts[index];
                      double margin = prod.price - prod.buyPrice;
                      int totalTerjual = salesCount[prod.id] ?? 0;

                      Color stockColor = Colors.green;
                      if (prod.stock == 0) {
                        stockColor = Colors.red;
                      } else if (prod.stock < 5) {
                        stockColor = Colors.amber[700]!;
                      }

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: stockColor,
                            child: Text(
                              '${prod.stock}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                            ),
                          ),
                          title: Text(prod.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              'Kategori: ${prod.category} | Terjual: $totalTerjual Pcs\nModal: ${currencyFormatter.format(prod.buyPrice)} | Jual: ${currencyFormatter.format(prod.price)}\nUntung: ${currencyFormatter.format(margin)} | Sisa Stok: ${prod.stock} Pcs'),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => showEditProductDialog(prod),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () {
                                  setState(() {
                                    products.removeWhere((p) => p.id == prod.id);
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void showAddProductDialog() {
    TextEditingController nameCtrl = TextEditingController();
    TextEditingController categoryCtrl = TextEditingController();
    TextEditingController buyPriceCtrl = TextEditingController();
    TextEditingController priceCtrl = TextEditingController();
    TextEditingController stockCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tambah Produk Baru'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Barang')),
              TextField(
                  controller: categoryCtrl,
                  decoration: const InputDecoration(labelText: 'Kategori (Cth: Sembako)')),
              TextField(
                  controller: buyPriceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Harga Beli / Modal (Rp)')),
              TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Harga Jual (Rp)')),
              TextField(
                  controller: stockCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Stok Awal')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                Product newProd = Product(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameCtrl.text,
                  category: categoryCtrl.text.isEmpty ? 'Umum' : categoryCtrl.text,
                  buyPrice: double.tryParse(buyPriceCtrl.text) ?? 0,
                  price: double.tryParse(priceCtrl.text) ?? 0,
                  stock: int.tryParse(stockCtrl.text) ?? 0,
                );
                setState(() {
                  products.add(newProd);
                });
                saveProductToGoogleSheets(newProd);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Produk berhasil ditambahkan & disimpan ke Google Sheets!')),
                );
              }
            },
            child: const Text('Simpan'),
          )
        ],
      ),
    );
  }

  void showEditProductDialog(Product product) {
    TextEditingController nameCtrl = TextEditingController(text: product.name);
    TextEditingController categoryCtrl = TextEditingController(text: product.category);
    TextEditingController buyPriceCtrl =
        TextEditingController(text: product.buyPrice.toInt().toString());
    TextEditingController priceCtrl =
        TextEditingController(text: product.price.toInt().toString());
    TextEditingController stockCtrl =
        TextEditingController(text: product.stock.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Produk'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Barang')),
              TextField(
                  controller: categoryCtrl,
                  decoration: const InputDecoration(labelText: 'Kategori')),
              TextField(
                  controller: buyPriceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Harga Beli / Modal (Rp)')),
              TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Harga Jual (Rp)')),
              TextField(
                  controller: stockCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Stok')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                product.name = nameCtrl.text;
                product.category =
                    categoryCtrl.text.isEmpty ? 'Umum' : categoryCtrl.text;
                product.buyPrice =
                    double.tryParse(buyPriceCtrl.text) ?? product.buyPrice;
                product.price =
                    double.tryParse(priceCtrl.text) ?? product.price;
                product.stock = int.tryParse(stockCtrl.text) ?? product.stock;
              });
              saveProductToGoogleSheets(product);
              Navigator.pop(context);
            },
            child: const Text('Update'),
          )
        ],
      ),
    );
  }

  // ================= 3. HALAMAN RIWAYAT & LAPORAN (HARIAN & BULANAN) =================
  Widget buildHistoryPage() {
    DateTime now = DateTime.now();

    double dailyOmset = transactions
        .where((trx) =>
            trx.date.year == now.year &&
            trx.date.month == now.month &&
            trx.date.day == now.day)
        .fold(0, (sum, trx) => sum + trx.total);
    double dailyProfit = transactions
        .where((trx) =>
            trx.date.year == now.year &&
            trx.date.month == now.month &&
            trx.date.day == now.day)
        .fold(0, (sum, trx) => sum + trx.netProfit);
    int dailyCount = transactions
        .where((trx) =>
            trx.date.year == now.year &&
            trx.date.month == now.month &&
            trx.date.day == now.day)
        .length;

    double monthlyOmset = transactions
        .where((trx) =>
            trx.date.year == now.year && trx.date.month == now.month)
        .fold(0, (sum, trx) => sum + trx.total);
    double monthlyProfit = transactions
        .where((trx) =>
            trx.date.year == now.year && trx.date.month == now.month)
        .fold(0, (sum, trx) => sum + trx.netProfit);
    int monthlyCount = transactions
        .where((trx) =>
            trx.date.year == now.year && trx.date.month == now.month)
        .length;

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '📅 Rekap Hari Ini (${DateFormat('dd MMM yyyy').format(now)})',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.green[900])),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text('Omset Harian',
                            style: TextStyle(fontSize: 11)),
                        Text(currencyFormatter.format(dailyOmset),
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800])),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('Laba Bersih',
                            style: TextStyle(fontSize: 11)),
                        Text(currencyFormatter.format(dailyProfit),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Center(
                    child: Text('$dailyCount Transaksi Berhasil',
                        style: const TextStyle(
                            fontSize: 11, fontStyle: FontStyle.italic))),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '📊 Rekap Bulan Ini (${DateFormat('MMMM yyyy', 'id_ID').format(now)})',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.blue[900])),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text('Omset Bulanan',
                            style: TextStyle(fontSize: 11)),
                        Text(currencyFormatter.format(monthlyOmset),
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800])),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('Laba Bersih',
                            style: TextStyle(fontSize: 11)),
                        Text(currencyFormatter.format(monthlyProfit),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Center(
                    child: Text('$monthlyCount Transaksi Berhasil',
                        style: const TextStyle(
                            fontSize: 11, fontStyle: FontStyle.italic))),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Daftar Riwayat Transaksi',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
          transactions.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(child: Text('Belum ada transaksi tercatat')),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final trx = transactions[transactions.length - 1 - index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      child: ListTile(
                        title: Text('Nota #${trx.id}'),
                        subtitle: Text(
                            '${DateFormat('dd/MM/yyyy HH:mm').format(trx.date)}\nItem: ${trx.itemsSummary.isNotEmpty ? trx.itemsSummary : "Detail tersimpan"}'),
                        trailing: Text(
                          currencyFormatter.format(trx.total),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                        onTap: () => showReceiptDialog(trx),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}
