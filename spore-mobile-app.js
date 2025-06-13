// App.tsx - Main React Native App
import React, { useEffect, useState } from 'react';
import {
  SafeAreaView,
  StyleSheet,
  ScrollView,
  View,
  Text,
  StatusBar,
  TouchableOpacity,
  RefreshControl,
  ActivityIndicator,
  Dimensions,
  Alert,
} from 'react-native';
import {
  NavigationContainer,
  DefaultTheme,
  DarkTheme,
} from '@react-navigation/native';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { WalletConnectModal, useWalletConnectModal } from '@walletconnect/modal-react-native';
import Icon from 'react-native-vector-icons/Ionicons';
import { LineChart, ProgressChart } from 'react-native-chart-kit';
import SporeSDK from '@sporeprotocol/sdk';
import { useColorScheme } from 'react-native';

const { width: screenWidth } = Dimensions.get('window');

// Initialize SDK
const sdk = new SporeSDK({
  apiUrl: 'https://api.sporeprotocol.io',
  wsUrl: 'wss://stream.sporeprotocol.io',
});

// Types
interface Organism {
  id: string;
  species: string;
  stage: string;
  biomass: number;
  health: number;
  lastUpdate: string;
}

interface ChartData {
  labels: string[];
  datasets: [{
    data: number[];
  }];
}

// Theme
const SporeTheme = {
  ...DefaultTheme,
  colors: {
    ...DefaultTheme.colors,
    primary: '#10b981',
    background: '#f3f4f6',
    card: '#ffffff',
    text: '#111827',
    border: '#e5e7eb',
  },
};

const SporeDarkTheme = {
  ...DarkTheme,
  colors: {
    ...DarkTheme.colors,
    primary: '#10b981',
    background: '#111827',
    card: '#1f2937',
    text: '#f9fafb',
    border: '#374151',
  },
};

// Navigation
const Tab = createBottomTabNavigator();
const Stack = createNativeStackNavigator();

// Components

const OrganismCard: React.FC<{ organism: Organism; onPress: () => void }> = ({ organism, onPress }) => {
  const getStageColor = (stage: string) => {
    const colors: { [key: string]: string } = {
      SEED: '#fbbf24',
      GERMINATION: '#84cc16',
      VEGETATIVE: '#22c55e',
      FLOWERING: '#ec4899',
      FRUITING: '#f97316',
      HARVEST: '#a855f7',
      DECAY: '#6b7280',
    };
    return colors[stage] || '#6b7280';
  };

  const getHealthColor = (health: number) => {
    if (health >= 80) return '#22c55e';
    if (health >= 60) return '#eab308';
    return '#ef4444';
  };

  return (
    <TouchableOpacity style={styles.card} onPress={onPress} activeOpacity={0.8}>
      <View style={styles.cardHeader}>
        <Text style={styles.cardTitle}>{organism.species} #{organism.id}</Text>
        <View style={[styles.stageBadge, { backgroundColor: getStageColor(organism.stage) }]}>
          <Text style={styles.stageBadgeText}>{organism.stage}</Text>
        </View>
      </View>
      
      <View style={styles.cardMetrics}>
        <View style={styles.metric}>
          <Icon name="leaf-outline" size={16} color="#10b981" />
          <Text style={styles.metricValue}>{organism.biomass.toFixed(0)} mg</Text>
          <Text style={styles.metricLabel}>Biomass</Text>
        </View>
        
        <View style={styles.metric}>
          <Icon name="heart-outline" size={16} color={getHealthColor(organism.health)} />
          <Text style={[styles.metricValue, { color: getHealthColor(organism.health) }]}>
            {organism.health.toFixed(0)}%
          </Text>
          <Text style={styles.metricLabel}>Health</Text>
        </View>
        
        <View style={styles.metric}>
          <Icon name="time-outline" size={16} color="#6b7280" />
          <Text style={styles.metricValue}>{organism.lastUpdate}</Text>
          <Text style={styles.metricLabel}>Updated</Text>
        </View>
      </View>
    </TouchableOpacity>
  );
};

// Screens

const DashboardScreen: React.FC = ({ navigation }: any) => {
  const [organisms, setOrganisms] = useState<Organism[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const { provider, isConnected, address, open } = useWalletConnectModal();

  useEffect(() => {
    loadOrganisms();
  }, [isConnected]);

  const loadOrganisms = async () => {
    try {
      setLoading(true);
      // Mock data for demonstration
      const mockOrganisms: Organism[] = [
        {
          id: '1',
          species: 'Tomato',
          stage: 'VEGETATIVE',
          biomass: 2500,
          health: 92,
          lastUpdate: '2 min ago',
        },
        {
          id: '2',
          species: 'Basil',
          stage: 'FLOWERING',
          biomass: 1800,
          health: 88,
          lastUpdate: '5 min ago',
        },
        {
          id: '3',
          species: 'Oyster Mushroom',
          stage: 'FRUITING',
          biomass: 3200,
          health: 95,
          lastUpdate: '1 hour ago',
        },
      ];
      setOrganisms(mockOrganisms);
    } catch (error) {
      Alert.alert('Error', 'Failed to load organisms');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const onRefresh = () => {
    setRefreshing(true);
    loadOrganisms();
  };

  if (!isConnected) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.connectContainer}>
          <Icon name="leaf" size={80} color="#10b981" />
          <Text style={styles.connectTitle}>Welcome to Spore Protocol</Text>
          <Text style={styles.connectSubtitle}>
            Connect your wallet to manage your biological organisms
          </Text>
          <TouchableOpacity style={styles.connectButton} onPress={open}>
            <Text style={styles.connectButtonText}>Connect Wallet</Text>
          </TouchableOpacity>
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
        }
      >
        <View style={styles.header}>
          <Text style={styles.greeting}>Hello, Grower! 🌱</Text>
          <Text style={styles.walletAddress}>{address?.slice(0, 6)}...{address?.slice(-4)}</Text>
        </View>

        <View style={styles.statsContainer}>
          <View style={styles.statCard}>
            <Text style={styles.statValue}>{organisms.length}</Text>
            <Text style={styles.statLabel}>Active Organisms</Text>
          </View>
          <View style={styles.statCard}>
            <Text style={styles.statValue}>
              {organisms.reduce((sum, o) => sum + o.biomass, 0).toFixed(0)}
            </Text>
            <Text style={styles.statLabel}>Total Biomass (mg)</Text>
          </View>
          <View style={styles.statCard}>
            <Text style={styles.statValue}>
              {(organisms.reduce((sum, o) => sum + o.health, 0) / organisms.length || 0).toFixed(0)}%
            </Text>
            <Text style={styles.statLabel}>Avg Health</Text>
          </View>
        </View>

        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Your Organisms</Text>
            <TouchableOpacity onPress={() => navigation.navigate('CreateOrganism')}>
              <Icon name="add-circle" size={28} color="#10b981" />
            </TouchableOpacity>
          </View>

          {loading ? (
            <ActivityIndicator size="large" color="#10b981" style={styles.loader} />
          ) : (
            organisms.map((organism) => (
              <OrganismCard
                key={organism.id}
                organism={organism}
                onPress={() => navigation.navigate('OrganismDetail', { organismId: organism.id })}
              />
            ))
          )}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
};

const OrganismDetailScreen: React.FC = ({ route, navigation }: any) => {
  const { organismId } = route.params;
  const [organism, setOrganism] = useState<Organism | null>(null);
  const [chartData, setChartData] = useState<ChartData>({
    labels: [],
    datasets: [{ data: [] }],
  });

  useEffect(() => {
    loadOrganismDetail();
  }, [organismId]);

  const loadOrganismDetail = async () => {
    // Mock data
    setOrganism({
      id: organismId,
      species: 'Tomato',
      stage: 'VEGETATIVE',
      biomass: 2500,
      health: 92,
      lastUpdate: '2 min ago',
    });

    // Mock chart data
    setChartData({
      labels: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      datasets: [{
        data: [2000, 2100, 2200, 2350, 2400, 2450, 2500],
      }],
    });
  };

  if (!organism) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color="#10b981" />
      </View>
    );
  }

  const progressData = {
    labels: ['Growth', 'Health', 'Resources'],
    data: [0.75, organism.health / 100, 0.85],
  };

  return (
    <ScrollView style={styles.container}>
      <View style={styles.detailHeader}>
        <Text style={styles.detailTitle}>{organism.species} #{organism.id}</Text>
        <Text style={styles.detailStage}>{organism.stage}</Text>
      </View>

      <View style={styles.chartContainer}>
        <Text style={styles.chartTitle}>Biomass Growth (7 days)</Text>
        <LineChart
          data={chartData}
          width={screenWidth - 40}
          height={220}
          chartConfig={{
            backgroundColor: '#ffffff',
            backgroundGradientFrom: '#ffffff',
            backgroundGradientTo: '#ffffff',
            decimalPlaces: 0,
            color: (opacity = 1) => `rgba(16, 185, 129, ${opacity})`,
            labelColor: (opacity = 1) => `rgba(107, 114, 128, ${opacity})`,
            style: {
              borderRadius: 16,
            },
            propsForDots: {
              r: '4',
              strokeWidth: '2',
              stroke: '#10b981',
            },
          }}
          bezier
          style={styles.chart}
        />
      </View>

      <View style={styles.chartContainer}>
        <Text style={styles.chartTitle}>Performance Metrics</Text>
        <ProgressChart
          data={progressData}
          width={screenWidth - 40}
          height={220}
          strokeWidth={16}
          radius={32}
          chartConfig={{
            backgroundColor: '#ffffff',
            backgroundGradientFrom: '#ffffff',
            backgroundGradientTo: '#ffffff',
            color: (opacity = 1) => `rgba(16, 185, 129, ${opacity})`,
            labelColor: (opacity = 1) => `rgba(107, 114, 128, ${opacity})`,
          }}
          hideLegend={false}
          style={styles.chart}
        />
      </View>

      <View style={styles.actionsContainer}>
        <TouchableOpacity style={styles.actionButton}>
          <Icon name="water-outline" size={24} color="#ffffff" />
          <Text style={styles.actionButtonText}>Add Water</Text>
        </TouchableOpacity>
        
        <TouchableOpacity style={styles.actionButton}>
          <Icon name="sunny-outline" size={24} color="#ffffff" />
          <Text style={styles.actionButtonText}>Adjust Light</Text>
        </TouchableOpacity>
        
        <TouchableOpacity style={[styles.actionButton, styles.secondaryButton]}>
          <Icon name="analytics-outline" size={24} color="#10b981" />
          <Text style={[styles.actionButtonText, { color: '#10b981' }]}>Full Report</Text>
        </TouchableOpacity>
      </View>
    </ScrollView>
  );
};

const MarketplaceScreen: React.FC = () => {
  const [listings, setListings] = useState([]);
  
  return (
    <ScrollView style={styles.container}>
      <View style={styles.marketHeader}>
        <Text style={styles.marketTitle}>Data Marketplace</Text>
        <Text style={styles.marketSubtitle}>Buy and sell biological data</Text>
      </View>
      
      <View style={styles.marketCategories}>
        <TouchableOpacity style={styles.categoryButton}>
          <Icon name="trending-up" size={24} color="#10b981" />
          <Text style={styles.categoryText}>Growth Data</Text>
        </TouchableOpacity>
        
        <TouchableOpacity style={styles.categoryButton}>
          <Icon name="flask" size={24} color="#10b981" />
          <Text style={styles.categoryText}>Experiments</Text>
        </TouchableOpacity>
        
        <TouchableOpacity style={styles.categoryButton}>
          <Icon name="bug" size={24} color="#10b981" />
          <Text style={styles.categoryText}>Disease Data</Text>
        </TouchableOpacity>
        
        <TouchableOpacity style={styles.categoryButton}>
          <Icon name="bulb" size={24} color="#10b981" />
          <Text style={styles.categoryText}>Optimizations</Text>
        </TouchableOpacity>
      </View>
      
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Featured Datasets</Text>
        
        <View style={styles.listingCard}>
          <Text style={styles.listingTitle}>Tomato Growth Optimization Dataset</Text>
          <Text style={styles.listingDescription}>
            100 days of growth data with environmental factors
          </Text>
          <View style={styles.listingFooter}>
            <Text style={styles.listingPrice}>0.1 ETH</Text>
            <TouchableOpacity style={styles.buyButton}>
              <Text style={styles.buyButtonText}>Purchase</Text>
            </TouchableOpacity>
          </View>
        </View>
        
        <View style={styles.listingCard}>
          <Text style={styles.listingTitle}>Hydroponic Basil Parameters</Text>
          <Text style={styles.listingDescription}>
            Optimal nutrient concentrations for hydroponic systems
          </Text>
          <View style={styles.listingFooter}>
            <Text style={styles.listingPrice}>0.05 ETH</Text>
            <TouchableOpacity style={styles.buyButton}>
              <Text style={styles.buyButtonText}>Purchase</Text>
            </TouchableOpacity>
          </View>
        </View>
      </View>
    </ScrollView>
  );
};

const ProfileScreen: React.FC = () => {
  const { disconnect, address } = useWalletConnectModal();
  
  return (
    <ScrollView style={styles.container}>
      <View style={styles.profileHeader}>
        <View style={styles.avatar}>
          <Icon name="person" size={40} color="#10b981" />
        </View>
        <Text style={styles.profileAddress}>{address?.slice(0, 8)}...{address?.slice(-6)}</Text>
      </View>
      
      <View style={styles.profileStats}>
        <View style={styles.profileStat}>
          <Text style={styles.profileStatValue}>12</Text>
          <Text style={styles.profileStatLabel}>Organisms</Text>
        </View>
        <View style={styles.profileStat}>
          <Text style={styles.profileStatValue}>8.5K</Text>
          <Text style={styles.profileStatLabel}>Total Biomass</Text>
        </View>
        <View style={styles.profileStat}>
          <Text style={styles.profileStatValue}>94%</Text>
          <Text style={styles.profileStatLabel}>Success Rate</Text>
        </View>
      </View>
      
      <View style={styles.menuSection}>
        <TouchableOpacity style={styles.menuItem}>
          <Icon name="document-text-outline" size={24} color="#6b7280" />
          <Text style={styles.menuItemText}>Transaction History</Text>
          <Icon name="chevron-forward" size={24} color="#6b7280" />
        </TouchableOpacity>
        
        <TouchableOpacity style={styles.menuItem}>
          <Icon name="notifications-outline" size={24} color="#6b7280" />
          <Text style={styles.menuItemText}>Notifications</Text>
          <Icon name="chevron-forward" size={24} color="#6b7280" />
        </TouchableOpacity>
        
        <TouchableOpacity style={styles.menuItem}>
          <Icon name="settings-outline" size={24} color="#6b7280" />
          <Text style={styles.menuItemText}>Settings</Text>
          <Icon name="chevron-forward" size={24} color="#6b7280" />
        </TouchableOpacity>
        
        <TouchableOpacity style={styles.menuItem}>
          <Icon name="help-circle-outline" size={24} color="#6b7280" />
          <Text style={styles.menuItemText}>Help & Support</Text>
          <Icon name="chevron-forward" size={24} color="#6b7280" />
        </TouchableOpacity>
      </View>
      
      <TouchableOpacity style={styles.disconnectButton} onPress={disconnect}>
        <Text style={styles.disconnectButtonText}>Disconnect Wallet</Text>
      </TouchableOpacity>
    </ScrollView>
  );
};

// Navigation Components

const DashboardStack = () => (
  <Stack.Navigator>
    <Stack.Screen 
      name="Dashboard" 
      component={DashboardScreen}
      options={{ headerShown: false }}
    />
    <Stack.Screen 
      name="OrganismDetail" 
      component={OrganismDetailScreen}
      options={{ 
        title: 'Organism Details',
        headerStyle: { backgroundColor: '#10b981' },
        headerTintColor: '#fff',
      }}
    />
  </Stack.Navigator>
);

const TabNavigator = () => {
  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        tabBarIcon: ({ focused, color, size }) => {
          let iconName;

          if (route.name === 'Home') {
            iconName = focused ? 'home' : 'home-outline';
          } else if (route.name === 'Marketplace') {
            iconName = focused ? 'cart' : 'cart-outline';
          } else if (route.name === 'Profile') {
            iconName = focused ? 'person' : 'person-outline';
          }

          return <Icon name={iconName} size={size} color={color} />;
        },
        tabBarActiveTintColor: '#10b981',
        tabBarInactiveTintColor: '#6b7280',
        headerShown: false,
      })}
    >
      <Tab.Screen name="Home" component={DashboardStack} />
      <Tab.Screen name="Marketplace" component={MarketplaceScreen} />
      <Tab.Screen name="Profile" component={ProfileScreen} />
    </Tab.Navigator>
  );
};

// Main App Component
const App: React.FC = () => {
  const isDarkMode = useColorScheme() === 'dark';
  const projectId = 'YOUR_WALLET_CONNECT_PROJECT_ID';
  
  const providerMetadata = {
    name: 'Spore Protocol',
    description: 'Manage your biological organisms on the blockchain',
    url: 'https://sporeprotocol.io',
    icons: ['https://sporeprotocol.io/icon.png'],
  };

  return (
    <>
      <StatusBar barStyle={isDarkMode ? 'light-content' : 'dark-content'} />
      <WalletConnectModal
        projectId={projectId}
        providerMetadata={providerMetadata}
      />
      <NavigationContainer theme={isDarkMode ? SporeDarkTheme : SporeTheme}>
        <TabNavigator />
      </NavigationContainer>
    </>
  );
};

// Styles
const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f3f4f6',
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  connectContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  connectTitle: {
    fontSize: 24,
    fontWeight: 'bold',
    marginTop: 20,
    marginBottom: 10,
  },
  connectSubtitle: {
    fontSize: 16,
    color: '#6b7280',
    textAlign: 'center',
    marginBottom: 30,
  },
  connectButton: {
    backgroundColor: '#10b981',
    paddingHorizontal: 30,
    paddingVertical: 15,
    borderRadius: 10,
  },
  connectButtonText: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: '600',
  },
  header: {
    padding: 20,
    backgroundColor: '#ffffff',
    borderBottomWidth: 1,
    borderBottomColor: '#e5e7eb',
  },
  greeting: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#111827',
  },
  walletAddress: {
    fontSize: 14,
    color: '#6b7280',
    marginTop: 5,
  },
  statsContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    padding: 20,
  },
  statCard: {
    flex: 1,
    backgroundColor: '#ffffff',
    padding: 15,
    borderRadius: 10,
    marginHorizontal: 5,
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 3,
    elevation: 3,
  },
  statValue: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#10b981',
  },
  statLabel: {
    fontSize: 12,
    color: '#6b7280',
    marginTop: 5,
  },
  section: {
    padding: 20,
  },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 15,
  },
  sectionTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#111827',
  },
  loader: {
    marginTop: 20,
  },
  card: {
    backgroundColor: '#ffffff',
    padding: 15,
    borderRadius: 10,
    marginBottom: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 3,
    elevation: 3,
  },
  cardHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 10,
  },
  cardTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#111827',
  },
  stageBadge: {
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: 5,
  },
  stageBadgeText: {
    color: '#ffffff',
    fontSize: 12,
    fontWeight: '600',
  },
  cardMetrics: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  metric: {
    alignItems: 'center',
  },
  metricValue: {
    fontSize: 16,
    fontWeight: '600',
    color: '#111827',
    marginTop: 5,
  },
  metricLabel: {
    fontSize: 12,
    color: '#6b7280',
    marginTop: 2,
  },
  detailHeader: {
    padding: 20,
    backgroundColor: '#ffffff',
    borderBottomWidth: 1,
    borderBottomColor: '#e5e7eb',
  },
  detailTitle: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#111827',
  },
  detailStage: {
    fontSize: 16,
    color: '#6b7280',
    marginTop: 5,
  },
  chartContainer: {
    padding: 20,
    backgroundColor: '#ffffff',
    marginTop: 10,
  },
  chartTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#111827',
    marginBottom: 10,
  },
  chart: {
    marginVertical: 8,
    borderRadius: 16,
  },
  actionsContainer: {
    padding: 20,
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'space-between',
  },
  actionButton: {
    flex: 1,
    backgroundColor: '#10b981',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 15,
    borderRadius: 10,
    margin: 5,
    minWidth: '45%',
  },
  secondaryButton: {
    backgroundColor: '#ffffff',
    borderWidth: 1,
    borderColor: '#10b981',
  },
  actionButtonText: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: '600',
    marginLeft: 5,
  },
  marketHeader: {
    padding: 20,
    backgroundColor: '#10b981',
  },
  marketTitle: {
    fontSize: 28,
    fontWeight: 'bold',
    color: '#ffffff',
  },
  marketSubtitle: {
    fontSize: 16,
    color: '#d1fae5',
    marginTop: 5,
  },
  marketCategories: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    padding: 10,
  },
  categoryButton: {
    flex: 1,
    backgroundColor: '#ffffff',
    alignItems: 'center',
    padding: 15,
    margin: 5,
    borderRadius: 10,
    minWidth: '45%',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 3,
    elevation: 3,
  },
  categoryText: {
    marginTop: 5,
    color: '#111827',
    fontSize: 14,
  },
  listingCard: {
    backgroundColor: '#ffffff',
    padding: 15,
    borderRadius: 10,
    marginBottom: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 3,
    elevation: 3,
  },
  listingTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#111827',
  },
  listingDescription: {
    fontSize: 14,
    color: '#6b7280',
    marginTop: 5,
  },
  listingFooter: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginTop: 15,
  },
  listingPrice: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#10b981',
  },
  buyButton: {
    backgroundColor: '#10b981',
    paddingHorizontal: 20,
    paddingVertical: 10,
    borderRadius: 5,
  },
  buyButtonText: {
    color: '#ffffff',
    fontWeight: '600',
  },
  profileHeader: {
    alignItems: 'center',
    padding: 30,
    backgroundColor: '#ffffff',
  },
  avatar: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: '#e0f2fe',
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 10,
  },
  profileAddress: {
    fontSize: 16,
    color: '#6b7280',
  },
  profileStats: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    paddingVertical: 20,
    backgroundColor: '#ffffff',
    borderBottomWidth: 1,
    borderBottomColor: '#e5e7eb',
  },
  profileStat: {
    alignItems: 'center',
  },
  profileStatValue: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#111827',
  },
  profileStatLabel: {
    fontSize: 14,
    color: '#6b7280',
    marginTop: 5,
  },
  menuSection: {
    backgroundColor: '#ffffff',
    marginTop: 10,
  },
  menuItem: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 20,
    borderBottomWidth: 1,
    borderBottomColor: '#e5e7eb',
  },
  menuItemText: {
    flex: 1,
    fontSize: 16,
    color: '#111827',
    marginLeft: 15,
  },
  disconnectButton: {
    margin: 20,
    padding: 15,
    backgroundColor: '#ef4444',
    borderRadius: 10,
    alignItems: 'center',
  },
  disconnectButtonText: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: '600',
  },
});

export default App;

---
// package.json - React Native dependencies

{
  "name": "SporeProtocolMobile",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "android": "react-native run-android",
    "ios": "react-native run-ios",
    "start": "react-native start",
    "test": "jest",
    "lint": "eslint . --ext .js,.jsx,.ts,.tsx",
    "pod-install": "cd ios && pod install",
    "clean": "watchman watch-del-all && rm -rf node_modules/ && npm cache clean --force && npm install"
  },
  "dependencies": {
    "@react-navigation/bottom-tabs": "^6.5.8",
    "@react-navigation/native": "^6.1.7",
    "@react-navigation/native-stack": "^6.9.13",
    "@react-native-async-storage/async-storage": "^1.19.1",
    "@walletconnect/modal-react-native": "^1.0.0",
    "@sporeprotocol/sdk": "^1.0.0",
    "react": "18.2.0",
    "react-native": "0.72.3",
    "react-native-chart-kit": "^6.12.0",
    "react-native-svg": "^13.10.0",
    "react-native-vector-icons": "^10.0.0",
    "react-native-safe-area-context": "^4.7.1",
    "react-native-screens": "^3.24.0",
    "react-native-gesture-handler": "^2.12.1",
    "react-native-reanimated": "^3.4.2",
    "ethers": "^6.7.0"
  },
  "devDependencies": {
    "@babel/core": "^7.20.0",
    "@babel/preset-env": "^7.20.0",
    "@babel/runtime": "^7.20.0",
    "@react-native/eslint-config": "^0.72.2",
    "@react-native/metro-config": "^0.72.9",
    "@tsconfig/react-native": "^3.0.0",
    "@types/react": "^18.0.24",
    "@types/react-native": "^0.72.2",
    "@types/react-native-vector-icons": "^6.4.14",
    "@typescript-eslint/eslint-plugin": "^5.59.11",
    "@typescript-eslint/parser": "^5.59.11",
    "babel-jest": "^29.2.1",
    "eslint": "^8.19.0",
    "jest": "^29.2.1",
    "metro-react-native-babel-preset": "0.76.7",
    "prettier": "^2.4.1",
    "react-test-renderer": "18.2.0",
    "typescript": "4.8.4"
  },
  "engines": {
    "node": ">=16"
  }
}