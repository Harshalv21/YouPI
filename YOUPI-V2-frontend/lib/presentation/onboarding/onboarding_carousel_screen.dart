import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';
import 'onboarding_viewmodel.dart';

class OnboardingCarouselScreen extends StatefulWidget {
  const OnboardingCarouselScreen({super.key});

  @override
  State<OnboardingCarouselScreen> createState() => _OnboardingCarouselScreenState();
}

class _OnboardingCarouselScreenState extends State<OnboardingCarouselScreen> {
  final PageController _pageController = PageController();

  static const _slides = [
    _Slide(AppStrings.slide1Title, AppStrings.slide1Body, Icons.phone_android_rounded, '📱'),
    _Slide(AppStrings.slide2Title, AppStrings.slide2Body, Icons.monetization_on_rounded, '🪙'),
    _Slide(AppStrings.slide3Title, AppStrings.slide3Body, Icons.credit_card_rounded, '💳'),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => OnboardingViewModel(),
      child: Consumer<OnboardingViewModel>(builder: (ctx, vm, _) {
        return Scaffold(
          backgroundColor: AppColors.backgroundPrimary,
          body: SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(AppDimensions.paddingPage),
                    child: TextButton(
                      onPressed: () => context.go('/auth/mobile'),
                      child: Text(AppStrings.onboardingSkip,
                          style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: vm.setPage,
                    itemCount: _slides.length,
                    itemBuilder: (ctx, i) => _SlideWidget(slide: _slides[i]),
                  ),
                ),
                // Dot indicators
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _slides.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: vm.currentPage == i ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: vm.currentPage == i ? AppColors.primary : AppColors.divider,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.all(AppDimensions.paddingPage),
                  child: YoupiButton(
                    label: vm.isLastPage ? AppStrings.onboardingGetStarted : AppStrings.onboardingNext,
                    onPressed: () {
                      if (vm.isLastPage) {
                        context.go('/auth/mobile');
                      } else {
                        vm.nextPage();
                        _pageController.nextPage(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOut);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _Slide {
  final String title;
  final String body;
  final IconData icon;
  final String emoji;
  const _Slide(this.title, this.body, this.icon, this.emoji);
}

class _SlideWidget extends StatelessWidget {
  final _Slide slide;
  const _SlideWidget({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingXXL),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              color: AppColors.backgroundCard,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 2),
              boxShadow: [BoxShadow(color: AppColors.primaryGlow, blurRadius: 30)],
            ),
            child: Center(
              child: Text(slide.emoji, style: const TextStyle(fontSize: 80)),
            ),
          ),
          const SizedBox(height: 40),
          Text(slide.title,
              style: AppTextStyles.headlineLarge, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(slide.body,
              style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
