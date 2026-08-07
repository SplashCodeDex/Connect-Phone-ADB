using System;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace DeXShareTarget
{
    public class ReceivePromptWindow : Window
    {
        private TaskCompletionSource<bool> tcs = new TaskCompletionSource<bool>();
        private bool _isClosing = false;

        
        public ReceivePromptWindow(string senderAlias, int fileCount)
        {
            Title = "DeX - Receive";
            Width = 420;
            Height = 160;
            WindowStartupLocation = WindowStartupLocation.Manual;
            Background = Brushes.Transparent;
            WindowStyle = WindowStyle.None;
            ResizeMode = ResizeMode.NoResize;
            Topmost = true;
            AllowsTransparency = true;

            this.Loaded += (s, e) =>
            {
                var workArea = SystemParameters.WorkArea;
                this.Left = workArea.Right - this.Width - 13;
                this.Top = workArea.Bottom - this.Height - 13;
                if (this.Left < workArea.Left) this.Left = workArea.Left + 13;
                if (this.Top < workArea.Top) this.Top = workArea.Top + 13;
            };

            string xaml = $@"
            <Border xmlns=""http://schemas.microsoft.com/winfx/2006/xaml/presentation""
                    xmlns:x=""http://schemas.microsoft.com/winfx/2006/xaml""
                    Background=""{{DynamicResource PrimaryBrush}}"" CornerRadius=""12"" BorderBrush=""{{DynamicResource AccentBrush}}"" BorderThickness=""1"" Margin=""10"" RenderTransformOrigin=""0.5,0.5"">
                <Border.RenderTransform>
                    <ScaleTransform ScaleX=""0.8"" ScaleY=""0.8""/>
                </Border.RenderTransform>
                <Border.Triggers>
                    <EventTrigger RoutedEvent=""Loaded"">
                        <BeginStoryboard>
                            <Storyboard>
                                <DoubleAnimation Storyboard.TargetProperty=""(UIElement.RenderTransform).(ScaleTransform.ScaleX)"" To=""1.0"" Duration=""0:0:0.4"">
                                    <DoubleAnimation.EasingFunction><BackEase Amplitude=""0.6"" EasingMode=""EaseOut""/></DoubleAnimation.EasingFunction>
                                </DoubleAnimation>
                                <DoubleAnimation Storyboard.TargetProperty=""(UIElement.RenderTransform).(ScaleTransform.ScaleY)"" To=""1.0"" Duration=""0:0:0.4"">
                                    <DoubleAnimation.EasingFunction><BackEase Amplitude=""0.6"" EasingMode=""EaseOut""/></DoubleAnimation.EasingFunction>
                                </DoubleAnimation>
                                <DoubleAnimation Storyboard.TargetProperty=""Opacity"" From=""0"" To=""1"" Duration=""0:0:0.2""/>
                            </Storyboard>
                        </BeginStoryboard>
                    </EventTrigger>
                </Border.Triggers>
                <Border.Effect>
                    <DropShadowEffect Color=""Black"" BlurRadius=""15"" ShadowDepth=""0"" Opacity=""0.5""/>
                </Border.Effect>
                <Border.Resources>
                    <Style TargetType=""Button"">
                        <Setter Property=""RenderTransformOrigin"" Value=""0.5,0.5""/>
                        <Setter Property=""RenderTransform"">
                            <Setter.Value>
                                <ScaleTransform ScaleX=""1.0"" ScaleY=""1.0""/>
                            </Setter.Value>
                        </Setter>
                        <Setter Property=""Template"">
                            <Setter.Value>
                                <ControlTemplate TargetType=""Button"">
                                    <Border Background=""{{TemplateBinding Background}}"" CornerRadius=""6"">
                                        <ContentPresenter HorizontalAlignment=""Center"" VerticalAlignment=""Center""/>
                                    </Border>
                                </ControlTemplate>
                            </Setter.Value>
                        </Setter>
                        <Style.Triggers>
                            <EventTrigger RoutedEvent=""MouseEnter"">
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetProperty=""(UIElement.RenderTransform).(ScaleTransform.ScaleX)"" To=""1.08"" Duration=""0:0:0.2"">
                                            <DoubleAnimation.EasingFunction><BackEase Amplitude=""1.2"" EasingMode=""EaseOut""/></DoubleAnimation.EasingFunction>
                                        </DoubleAnimation>
                                        <DoubleAnimation Storyboard.TargetProperty=""(UIElement.RenderTransform).(ScaleTransform.ScaleY)"" To=""1.08"" Duration=""0:0:0.2"">
                                            <DoubleAnimation.EasingFunction><BackEase Amplitude=""1.2"" EasingMode=""EaseOut""/></DoubleAnimation.EasingFunction>
                                        </DoubleAnimation>
                                    </Storyboard>
                                </BeginStoryboard>
                            </EventTrigger>
                            <EventTrigger RoutedEvent=""MouseLeave"">
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetProperty=""(UIElement.RenderTransform).(ScaleTransform.ScaleX)"" To=""1.0"" Duration=""0:0:0.2"">
                                            <DoubleAnimation.EasingFunction><BackEase Amplitude=""0.5"" EasingMode=""EaseOut""/></DoubleAnimation.EasingFunction>
                                        </DoubleAnimation>
                                        <DoubleAnimation Storyboard.TargetProperty=""(UIElement.RenderTransform).(ScaleTransform.ScaleY)"" To=""1.0"" Duration=""0:0:0.2"">
                                            <DoubleAnimation.EasingFunction><BackEase Amplitude=""0.5"" EasingMode=""EaseOut""/></DoubleAnimation.EasingFunction>
                                        </DoubleAnimation>
                                    </Storyboard>
                                </BeginStoryboard>
                            </EventTrigger>
                        </Style.Triggers>
                    </Style>
                </Border.Resources>
                <Grid Margin=""20,15,20,15"">
                    <Grid.RowDefinitions>
                        <RowDefinition Height=""Auto""/>
                        <RowDefinition Height=""*"" />
                        <RowDefinition Height=""Auto""/>
                    </Grid.RowDefinitions>
                    
                    <TextBlock Text=""Incoming Transfer"" FontSize=""16"" FontWeight=""Bold"" Foreground=""{{DynamicResource PrimaryTextBrush}}"" Grid.Row=""0"" Margin=""0,0,0,5""/>
                    
                    <TextBlock Text=""{senderAlias} wants to send {fileCount} file(s)."" FontSize=""14"" Foreground=""{{DynamicResource SecondaryTextBrush}}"" Grid.Row=""1"" Margin=""0,0,0,15"" TextTrimming=""CharacterEllipsis""/>
                    
                    <StackPanel Grid.Row=""2"" Orientation=""Horizontal"" HorizontalAlignment=""Right"">
                        <Button x:Name=""btnDecline"" Content=""Decline"" Width=""80"" Height=""32"" Margin=""0,0,12,0"" FontSize=""14""
                                Background=""{{DynamicResource AccentBrush}}"" Foreground=""{{DynamicResource PrimaryTextBrush}}"" BorderThickness=""0""/>
                        <Button x:Name=""btnAccept"" Content=""Accept"" Width=""80"" Height=""32"" FontSize=""14""
                                Background=""{{DynamicResource SecondaryBrush}}"" Foreground=""{{DynamicResource SecondaryForegroundBrush}}"" BorderThickness=""0"" FontWeight=""Bold""/>
                    </StackPanel>
                </Grid>
            </Border>";

            string themeName = "DarkTheme";
            try 
            {
                var txt = System.IO.File.ReadAllText(System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeX", "theme.json"));
                if (txt.Contains("LightTheme")) themeName = "LightTheme";
            } catch {}
            var dict = (ResourceDictionary)System.Windows.Markup.XamlReader.Load(new System.IO.FileStream(System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Themes", themeName + ".xaml"), System.IO.FileMode.Open, System.IO.FileAccess.Read));
            this.Resources.MergedDictionaries.Add(dict);

            var rootBorder = (Border)System.Windows.Markup.XamlReader.Parse(xaml);
            
            var btnDecline = (Button)rootBorder.FindName("btnDecline");
            var btnAccept = (Button)rootBorder.FindName("btnAccept");

            btnDecline.Click += (s, e) => { tcs.TrySetResult(false); CloseWithAnimation(); };
            btnAccept.Click += (s, e) => { tcs.TrySetResult(true); CloseWithAnimation(); };
            this.Closed += (s, e) => { tcs.TrySetResult(false); };

            Content = rootBorder;
            this.MouseLeftButtonDown += (s, e) => this.DragMove();
        }

        private void CloseWithAnimation()
        {
            if (_isClosing) return;
            _isClosing = true;

            var sb = new System.Windows.Media.Animation.Storyboard();
            
            var scaleXAnim = new System.Windows.Media.Animation.DoubleAnimation { To = 0.8, Duration = TimeSpan.FromMilliseconds(250) };
            scaleXAnim.EasingFunction = new System.Windows.Media.Animation.BackEase { Amplitude = 0.5, EasingMode = System.Windows.Media.Animation.EasingMode.EaseIn };
            System.Windows.Media.Animation.Storyboard.SetTarget(scaleXAnim, (UIElement)Content);
            System.Windows.Media.Animation.Storyboard.SetTargetProperty(scaleXAnim, new PropertyPath("(UIElement.RenderTransform).(ScaleTransform.ScaleX)"));
            sb.Children.Add(scaleXAnim);

            var scaleYAnim = new System.Windows.Media.Animation.DoubleAnimation { To = 0.8, Duration = TimeSpan.FromMilliseconds(250) };
            scaleYAnim.EasingFunction = new System.Windows.Media.Animation.BackEase { Amplitude = 0.5, EasingMode = System.Windows.Media.Animation.EasingMode.EaseIn };
            System.Windows.Media.Animation.Storyboard.SetTarget(scaleYAnim, (UIElement)Content);
            System.Windows.Media.Animation.Storyboard.SetTargetProperty(scaleYAnim, new PropertyPath("(UIElement.RenderTransform).(ScaleTransform.ScaleY)"));
            sb.Children.Add(scaleYAnim);

            var opacityAnim = new System.Windows.Media.Animation.DoubleAnimation { To = 0, Duration = TimeSpan.FromMilliseconds(200) };
            System.Windows.Media.Animation.Storyboard.SetTarget(opacityAnim, this);
            System.Windows.Media.Animation.Storyboard.SetTargetProperty(opacityAnim, new PropertyPath("Opacity"));
            sb.Children.Add(opacityAnim);

            sb.Completed += (s, e) => { this.Close(); };
            sb.Begin();
        }

        public Task<bool> WaitForResponseAsync()
        {
            return tcs.Task;
        }
    }
}
