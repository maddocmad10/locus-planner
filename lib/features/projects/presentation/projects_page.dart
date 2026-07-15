import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Projects'), automaticallyImplyLeading: false),
      floatingActionButton: FloatingActionButton(onPressed: (){}, child: Icon(Icons.add)),
      body: Padding(padding: EdgeInsets.all(24), child: GridView.count(crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, children: [
        Card(child: Padding(padding: EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Locus Windows App', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 12),
          LinearProgressIndicator(value: 0.65),
          Spacer(),
          SizedBox(height: 100, child: LineChart(LineChartData(gridData: FlGridData(show: false), titlesData: FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: [FlSpot(0,0.2), FlSpot(1,0.4), FlSpot(2,0.5), FlSpot(3,0.65)], isCurved: true, barWidth: 3, dotData: FlDotData(show: false), color: Theme.of(context).colorScheme.primary)]))),
        ]))),
      ])),
    );
  }
}
